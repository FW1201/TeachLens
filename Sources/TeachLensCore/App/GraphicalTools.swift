import AppKit
import SwiftUI

/// Geometry for the floating launcher and its upward tool column. Kept free of
/// AppKit state so the self-tests can check it.
enum GraphicalToolsLayout {
    static let width: CGFloat = 58
    static let collapsedHeight: CGFloat = 56
    static let maxExpandedHeight: CGFloat = 540
    /// Room kept above the launcher so the column always has space to open.
    static let minimumRoomAbove: CGFloat = 190
    static let margin: CGFloat = 16

    /// Default dock: bottom-right corner of the visible frame.
    static func defaultOrigin(in bounds: CGRect) -> CGPoint {
        CGPoint(x: bounds.maxX - width - margin, y: bounds.minY + margin)
    }

    /// Keeps the launcher fully on screen and leaves room above it to expand.
    static func clampedOrigin(_ origin: CGPoint, in bounds: CGRect) -> CGPoint {
        let x = min(max(origin.x, bounds.minX), max(bounds.minX, bounds.maxX - width))
        let y = min(max(origin.y, bounds.minY), max(bounds.minY, bounds.maxY - minimumRoomAbove))
        return CGPoint(x: x, y: y)
    }

    /// Height of the panel when the column is open; the panel grows upward from
    /// the launcher and scrolls when the screen is short.
    static func expandedHeight(originY: CGFloat, in bounds: CGRect) -> CGFloat {
        max(collapsedHeight, min(maxExpandedHeight, bounds.maxY - originY))
    }
}

/// The optional floating round launcher ("Graphical Mode"). Clicking it opens a
/// single vertical column of tool icons directly above it.
@MainActor
final class GraphicalTools: ObservableObject {
    static let preference = "graphicalToolsEnabled"
    private static let positionKey = "graphicalToolsPosition"

    @Published private(set) var expanded = false
    @Published var recording = false
    /// Which toggle tools are currently on, refreshed whenever the column opens
    /// and shortly after a tool runs.
    @Published private(set) var activeTools: Set<Tool> = []
    @Published private(set) var currentCourseModeID: String?

    enum Tool: Hashable { case keystrokes, spotlight, captions, whiteboard }

    private let teaching: TeachingControllers
    private var panel: ToolsPanel?
    private var dragOffset: NSPoint?
    private var lastDragEnded = Date.distantPast
    private var enabled = false
    private var captureActive = false
    private var outsideClickMonitor: Any?

    init(teaching: TeachingControllers) {
        self.teaching = teaching
    }

    var windowNumber: Int? {
        guard let panel, panel.isVisible else { return nil }
        return panel.windowNumber
    }

    // MARK: Visibility

    func setVisible(_ visible: Bool) {
        enabled = visible
        updateVisibility()
    }

    /// Hides the launcher while zoom, drawing, typing, the break timer or a
    /// region selection is on screen, and brings it back afterwards.
    func setCaptureActive(_ active: Bool) {
        guard captureActive != active else { return }
        captureActive = active
        updateVisibility()
    }

    func screenConfigurationChanged() {
        guard let panel, panel.isVisible else { return }
        place(at: panel.frame.origin)
    }

    /// Re-renders the labels after the app language changes.
    func languageChanged() {
        objectWillChange.send()
    }

    private func updateVisibility() {
        guard enabled, !captureActive else {
            collapse()
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        let saved = UserDefaults.standard.dictionary(forKey: Self.positionKey)
        if let x = saved?["x"] as? Double, let y = saved?["y"] as? Double {
            place(at: NSPoint(x: x, y: y))
        } else if let bounds = NSScreen.main?.visibleFrame {
            place(at: GraphicalToolsLayout.defaultOrigin(in: bounds))
        }
        refreshState()
        panel.orderFrontRegardless()
    }

    private func makePanel() -> ToolsPanel {
        let window = ToolsPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Recording, panorama and screenshots build their filters without an
        // exclusion list, so keep the launcher out of every capture here.
        window.sharingType = .none
        window.setAccessibilityLabel(L10n.t("TeachLens Tools", "TeachLens 教學工具"))
        window.contentView = NSHostingView(rootView: GraphicalToolsView(tools: self))
        window.onDismiss = { [weak self] in self?.collapse() }
        panel = window
        return window
    }

    /// Places the launcher on whichever screen holds `origin` (falling back to
    /// the main screen when that display was removed).
    private func place(at origin: NSPoint) {
        guard let panel else { return }
        let screen = NSScreen.screens.first { $0.visibleFrame.insetBy(dx: -1, dy: -1).contains(origin) }
            ?? NSScreen.main
        guard let bounds = screen?.visibleFrame else { return }
        let clamped = GraphicalToolsLayout.clampedOrigin(origin, in: bounds)
        let height = expanded
            ? GraphicalToolsLayout.expandedHeight(originY: clamped.y, in: bounds)
            : GraphicalToolsLayout.collapsedHeight
        panel.setFrame(NSRect(x: clamped.x, y: clamped.y, width: GraphicalToolsLayout.width, height: height),
                       display: true)
    }

    // MARK: Dragging

    fileprivate func moveLauncher() {
        guard !expanded, let panel else { return }
        let mouse = NSEvent.mouseLocation
        if dragOffset == nil {
            dragOffset = NSPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
        }
        if let dragOffset {
            place(at: NSPoint(x: mouse.x - dragOffset.x, y: mouse.y - dragOffset.y))
        }
    }

    fileprivate func finishMovingLauncher() {
        guard dragOffset != nil, let panel else { return }
        dragOffset = nil
        lastDragEnded = Date()
        UserDefaults.standard.set(["x": Double(panel.frame.minX), "y": Double(panel.frame.minY)],
                                  forKey: Self.positionKey)
    }

    // MARK: Expand / collapse

    fileprivate func toggleExpanded() {
        // A drag ends with a mouse-up over the button; don't treat it as a click.
        if dragOffset != nil || Date().timeIntervalSince(lastDragEnded) < 0.3 { return }
        if expanded {
            collapse()
        } else {
            expand()
        }
    }

    private func expand() {
        guard let panel else { return }
        refreshState()
        expanded = true
        place(at: panel.frame.origin)
        panel.makeKey()
        if outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.collapse() }
            }
        }
    }

    fileprivate func collapse() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        guard expanded else { return }
        expanded = false
        if let panel { place(at: panel.frame.origin) }
    }

    // MARK: Commands and live state

    fileprivate func run(_ command: AppCommand) {
        collapse()
        teaching.run(command)
        scheduleRefresh()
    }

    fileprivate func apply(_ mode: CourseMode) {
        collapse()
        teaching.courseModes.apply(mode)
        scheduleRefresh()
    }

    /// Toggles such as captions start asynchronously, so read the state again
    /// after they have had a moment to settle.
    private func scheduleRefresh() {
        refreshState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated { self?.refreshState() }
        }
    }

    func refreshState() {
        var active: Set<Tool> = []
        if teaching.keystrokes.isActive { active.insert(.keystrokes) }
        if teaching.spotlight.spotlightOn { active.insert(.spotlight) }
        if teaching.captions.isRunning { active.insert(.captions) }
        if teaching.whiteboard.isVisible { active.insert(.whiteboard) }
        if active != activeTools { activeTools = active }
        let modeID = teaching.courseModes.currentModeID
        if modeID != currentCourseModeID { currentCourseModeID = modeID }
    }

    fileprivate var courseModes: [CourseMode] { teaching.courseModes.allModes }
}

// MARK: - Views

private struct GraphicalToolsView: View {
    @ObservedObject var tools: GraphicalTools

    var body: some View {
        VStack(spacing: 5) {
            if tools.expanded {
                column
            }
            launcher
                .frame(height: 50)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { _ in tools.moveLauncher() }
                        .onEnded { _ in tools.finishMovingLauncher() }
                )
        }
        .padding(3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onExitCommand { tools.collapse() }
    }

    // MARK: Column

    @ViewBuilder private var column: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            list.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 23))
        } else {
            list.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 23))
        }
        #else
        list.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 23))
        #endif
    }

    /// Listed top to bottom; the launcher sits below, so reading upward from the
    /// launcher gives Course Modes, Keystrokes, Spotlight, … More.
    private var list: some View {
        ScrollView {
            VStack(spacing: 5) {
                menu(L10n.t("More tools", "更多工具"), "ellipsis") {
                    item(L10n.t("Recognize Text", "辨識文字"), .snipOcr)
                    item(L10n.t("Copy Panorama", "複製長截圖"), .startPanorama(save: false))
                    item(L10n.t("Save Panorama", "儲存長截圖"), .startPanorama(save: true))
                    #if !TEACHLENS_APP_STORE
                    item("DemoType", .startDemoType)
                    #endif
                    item("DemoMirror", .toggleDemoMirror(scope: .screen))
                }
                if tools.recording {
                    button(L10n.t("Stop Recording", "停止錄影"), "stop.circle.fill",
                           .toggleRecording(region: false), isOn: true, tint: .red)
                } else {
                    menu(L10n.t("Record", "錄影"), "record.circle") {
                        item(L10n.t("Entire Screen", "全螢幕"), .toggleRecording(region: false))
                        item(L10n.t("Region", "區域"), .toggleRecording(region: true))
                    }
                }
                menu(L10n.t("Screenshot", "截圖"), "camera.viewfinder") {
                    item(L10n.t("Copy Region", "複製區域"), .snipRegion(save: false))
                    item(L10n.t("Save Region", "儲存區域"), .snipRegion(save: true))
                }
                button(L10n.t("Break Timer", "休息計時"), "timer", .toggleBreakTimer)
                button(L10n.t("Captions", "字幕"), "captions.bubble", .toggleCaptions,
                       isOn: tools.activeTools.contains(.captions))
                button(L10n.t("Whiteboard", "白板"), "rectangle.and.pencil.and.ellipsis", .toggleWhiteboard,
                       isOn: tools.activeTools.contains(.whiteboard))
                button(L10n.t("Draw", "畫筆"), "pencil.tip", .activateDrawWithoutZoom)
                menu(L10n.t("Zoom", "放大"), "magnifyingglass") {
                    item(L10n.t("Static Zoom", "靜態放大"), .activateStaticZoom)
                    item(L10n.t("Live Zoom", "即時放大"), .activateLiveZoom)
                }
                button(L10n.t("Spotlight", "聚光燈"), "lightbulb", .toggleSpotlight,
                       isOn: tools.activeTools.contains(.spotlight))
                button(L10n.t("Keystrokes", "按鍵顯示"), "command", .toggleKeystrokes,
                       isOn: tools.activeTools.contains(.keystrokes))
                menu(L10n.t("Course Modes", "課程模式"), "square.stack") {
                    ForEach(tools.courseModes) { mode in
                        Button {
                            tools.apply(mode)
                        } label: {
                            if mode.id == tools.currentCourseModeID {
                                Label(mode.name, systemImage: "checkmark")
                            } else {
                                Text(mode.name)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Building blocks

    private func icon(_ systemName: String, isOn: Bool, tint: Color) -> some View {
        Image(systemName: systemName)
            .foregroundStyle(isOn ? tint : Color.primary)
            .frame(width: 30, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isOn ? tint.opacity(0.22) : Color.clear)
            )
            .contentShape(Rectangle())
    }

    /// `isOn` is nil for one-shot actions; for toggles it drives the highlight
    /// and what VoiceOver reads.
    private func button(_ title: String, _ systemName: String, _ command: AppCommand,
                        isOn: Bool? = nil, tint: Color = .accentColor) -> some View {
        let on = isOn ?? false
        let state = on ? L10n.t("On", "開啟") : L10n.t("Off", "關閉")
        return Button { tools.run(command) } label: { icon(systemName, isOn: on, tint: tint) }
            .buttonStyle(.plain)
            .help(isOn == nil ? title : "\(title)（\(state)）")
            .accessibilityLabel(title)
            .accessibilityValue(isOn == nil ? "" : state)
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func menu<Content: View>(_ title: String, _ systemName: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            icon(systemName, isOn: false, tint: .accentColor)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 30, height: 28)
        .help(title)
        .accessibilityLabel(title)
    }

    private func item(_ title: String, _ command: AppCommand) -> some View {
        Button(title) { tools.run(command) }
    }

    // MARK: Launcher

    @ViewBuilder private var launcher: some View {
        let title = tools.expanded
            ? L10n.t("Collapse Tools", "收合教學工具")
            : L10n.t("Expand Tools", "展開教學工具")
        let symbol = tools.expanded ? "chevron.down" : (tools.recording ? "record.circle.fill" : "square.grid.2x2")
        let control = Button { tools.toggleExpanded() } label: {
            Image(systemName: symbol)
                .foregroundStyle(tools.recording && !tools.expanded ? Color.red : Color.primary)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(tools.recording ? L10n.t("Recording", "錄影中") : "")
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            control.buttonStyle(.glass).buttonBorderShape(.circle)
        } else {
            control.buttonStyle(.plain).background(.regularMaterial, in: Circle())
        }
        #else
        control.buttonStyle(.plain).background(.regularMaterial, in: Circle())
        #endif
    }
}

// MARK: - Panel

private final class ToolsPanel: NSPanel {
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onDismiss?() }

    override func resignKey() {
        super.resignKey()
        onDismiss?()
    }
}
