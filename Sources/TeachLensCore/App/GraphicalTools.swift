import AppKit
import SwiftUI

/// Geometry for the floating launcher and its upward tool column. Kept free of
/// AppKit state so the self-tests can check it.
enum GraphicalToolsLayout {
    /// Icon (30) plus a 10 pt glass rim on each side: snug around the icons.
    static let width: CGFloat = 50
    static let collapsedHeight: CGFloat = 56
    static let maxExpandedHeight: CGFloat = 600
    /// Room kept above the launcher so the column always has space to open.
    static let minimumRoomAbove: CGFloat = 190
    /// Default dock distance from the screen corner.
    static let margin: CGFloat = 24
    /// Closest the launcher may be dragged to any screen edge.
    static let edgeInset: CGFloat = 16
    /// Panel padding (3 on each side), the gap between column and launcher,
    /// and the column's own vertical padding and row spacing.
    static let panelPadding: CGFloat = 6
    static let columnGap: CGFloat = 5
    static let columnPadding: CGFloat = 20
    static let rowSpacing: CGFloat = 10
    /// The "students can't see this" marker row under the tools.
    static let markerHeight: CGFloat = 24

    static func width(scale: CGFloat) -> CGFloat { width * scale }
    static func collapsedHeight(scale: CGFloat) -> CGFloat { panelPadding + 50 * scale }

    /// Height the column needs for `items` icon rows (tools plus More) and the
    /// marker, so the glass column fits its content with no empty space.
    static func columnHeight(items: Int, scale: CGFloat) -> CGFloat {
        let rows = CGFloat(max(1, items))
        return columnPadding + rows * TeachLensChrome.iconHeight * scale + (rows - 1) * rowSpacing
            + rowSpacing + markerHeight * scale
    }

    /// Default dock: bottom-right corner of the visible frame.
    static func defaultOrigin(in bounds: CGRect, scale: CGFloat = 1) -> CGPoint {
        CGPoint(x: bounds.maxX - width(scale: scale) - margin, y: bounds.minY + margin)
    }

    /// Keeps the launcher fully on screen and leaves room above it to expand.
    static func clampedOrigin(_ origin: CGPoint, in bounds: CGRect, scale: CGFloat = 1) -> CGPoint {
        let minX = bounds.minX + edgeInset
        let minY = bounds.minY + edgeInset
        let x = min(max(origin.x, minX), max(minX, bounds.maxX - width(scale: scale) - edgeInset))
        let y = min(max(origin.y, minY), max(minY, bounds.maxY - minimumRoomAbove))
        return CGPoint(x: x, y: y)
    }

    /// Where the launcher goes when its size changes: a toolbar docked on the
    /// right half of the screen keeps its right edge (so Large does not grow
    /// into the screen edge), one on the left keeps its left edge.
    static func resizedOrigin(from frame: CGRect, toScale scale: CGFloat, in bounds: CGRect) -> CGPoint {
        let newWidth = width(scale: scale)
        let x = frame.midX > bounds.midX ? frame.maxX - newWidth : frame.minX
        return clampedOrigin(CGPoint(x: x, y: frame.minY), in: bounds, scale: scale)
    }

    /// Height of the panel when the column is open: just enough for the
    /// column, growing upward from the launcher; on a short screen it is
    /// capped and the column scrolls.
    static func expandedHeight(originY: CGFloat, in bounds: CGRect,
                               items: Int = ToolbarTool.defaultPinned.count + 1, scale: CGFloat = 1) -> CGFloat {
        let wanted = collapsedHeight(scale: scale) + columnGap + columnHeight(items: items, scale: scale)
        return max(collapsedHeight(scale: scale), min(wanted, bounds.maxY - originY))
    }
}

/// The floating toolbar's size: Small, Medium (standard) or Large buttons.
enum ToolbarSize: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large

    var id: String { rawValue }

    var scale: CGFloat {
        switch self {
        case .small: return 0.85
        case .medium: return 1
        case .large: return 1.3
        }
    }

    var title: String {
        switch self {
        case .small: return L10n.t("Small", "小")
        case .medium: return L10n.t("Medium", "中")
        case .large: return L10n.t("Large", "大")
        }
    }
}

/// Every tool the floating toolbar can carry. The toolbar shows the pinned
/// ones (six by default) and keeps the rest in "More".
enum ToolbarTool: String, CaseIterable, Identifiable, Sendable {
    // Listed from the launcher upward.
    case courseModes, keystrokes, spotlight, zoom, draw, whiteboard, captions, breakTimer, screenshot, record

    var id: String { rawValue }

    static let defaultPinned: [ToolbarTool] = [.courseModes, .keystrokes, .spotlight, .draw, .whiteboard, .record]

    var title: String {
        switch self {
        case .courseModes: return L10n.t("Course Modes", "課程模式")
        case .keystrokes: return L10n.t("Keystrokes", "按鍵顯示")
        case .spotlight: return L10n.t("Spotlight", "聚光燈")
        case .zoom: return L10n.t("Zoom", "放大")
        case .draw: return L10n.t("Draw", "畫筆")
        case .whiteboard: return L10n.t("Whiteboard", "白板")
        case .captions: return L10n.t("Captions", "字幕")
        case .breakTimer: return L10n.t("Timers", "計時")
        case .screenshot: return L10n.t("Screenshot", "截圖")
        case .record: return L10n.t("Record", "錄影")
        }
    }

    var symbol: String {
        switch self {
        case .courseModes: return "square.stack"
        case .keystrokes: return "command"
        case .spotlight: return "lightbulb"
        case .zoom: return "magnifyingglass"
        case .draw: return "pencil.tip"
        case .whiteboard: return "rectangle.and.pencil.and.ellipsis"
        case .captions: return "captions.bubble"
        case .breakTimer: return "timer"
        case .screenshot: return "camera.viewfinder"
        case .record: return "record.circle"
        }
    }

    /// Colour of the status dot on the launcher while the tool is on.
    var dotColor: Color {
        switch self {
        case .keystrokes: return .blue
        case .spotlight: return .yellow
        case .captions: return .purple
        case .whiteboard: return .green
        case .record: return .red
        default: return .gray
        }
    }
}

/// The optional floating round launcher ("Graphical Mode"). Clicking it opens a
/// single vertical column of tool icons directly above it.
@MainActor
final class GraphicalTools: ObservableObject {
    static let preference = "graphicalToolsEnabled"
    static let pinnedKey = "graphicalToolsPinned"
    static let sizeKey = "graphicalToolsSize"
    private static let positionKey = "graphicalToolsPosition"

    @Published private(set) var expanded = false
    @Published var recording = false {
        didSet { refreshState() }
    }
    /// Which toggle tools are currently on; refreshed on open, after a tool
    /// runs, and every couple of seconds while the launcher is visible (so the
    /// status dots follow shortcuts used elsewhere).
    @Published private(set) var activeTools: Set<ToolbarTool> = []
    @Published private(set) var currentCourseModeID: String?
    @Published private(set) var pinned: [ToolbarTool]
    @Published private(set) var size: ToolbarSize
    /// True after a few idle seconds: the launcher fades back so it doesn't
    /// distract while teaching.
    @Published private(set) var idle = false

    private let teaching: TeachingControllers
    private var panel: ToolsPanel?
    private var dragOffset: NSPoint?
    private var lastDragEnded = Date.distantPast
    private var enabled = false
    private var captureActive = false
    private var outsideClickMonitor: Any?
    private var stateTimer: Timer?
    private var idleTask: Task<Void, Never>?
    /// The panel's frame is tall while the column is open or animating closed;
    /// `expanded` drives what the view shows.
    private var panelTall = false

    static let idleDelay: TimeInterval = 5

    /// The column slides up from the launcher; with Reduce Motion it fades.
    private static var openAnimation: Animation {
        TeachLensChrome.reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.86)
    }
    private static let closeDuration: TimeInterval = 0.18

    init(teaching: TeachingControllers) {
        self.teaching = teaching
        let saved = UserDefaults.standard.stringArray(forKey: Self.pinnedKey)?.compactMap(ToolbarTool.init(rawValue:))
        self.pinned = (saved?.isEmpty == false ? saved : nil) ?? ToolbarTool.defaultPinned
        self.size = UserDefaults.standard.string(forKey: Self.sizeKey).flatMap(ToolbarSize.init(rawValue:)) ?? .medium
    }

    fileprivate func setSize(_ newSize: ToolbarSize) {
        guard newSize != size else { return }
        size = newSize
        UserDefaults.standard.set(newSize.rawValue, forKey: Self.sizeKey)
        guard let panel else { return }
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(panel.frame) } ?? NSScreen.main
        guard let bounds = screen?.visibleFrame else { return place(at: panel.frame.origin) }
        place(at: GraphicalToolsLayout.resizedOrigin(from: panel.frame, toScale: newSize.scale, in: bounds))
    }

    /// Icon rows in the open column: the pinned tools plus More.
    private var columnItems: Int { pinned.count + 1 }

    var windowNumber: Int? {
        guard let panel, panel.isVisible else { return nil }
        return panel.windowNumber
    }

    // MARK: Pinned tools

    /// Pinned tools in their fixed order (from the launcher upward).
    var pinnedInOrder: [ToolbarTool] { ToolbarTool.allCases.filter { pinned.contains($0) } }
    var unpinned: [ToolbarTool] { ToolbarTool.allCases.filter { !pinned.contains($0) } }

    fileprivate func togglePinned(_ tool: ToolbarTool) {
        if pinned.contains(tool) {
            guard pinned.count > 1 else { return }
            pinned.removeAll { $0 == tool }
        } else {
            pinned.append(tool)
        }
        UserDefaults.standard.set(pinned.map(\.rawValue), forKey: Self.pinnedKey)
        if let panel { place(at: panel.frame.origin) }
    }

    fileprivate func resetPinned() {
        pinned = ToolbarTool.defaultPinned
        UserDefaults.standard.removeObject(forKey: Self.pinnedKey)
        if let panel { place(at: panel.frame.origin) }
    }

    // MARK: Shortcuts

    /// Shortcuts for the tooltips, read once each time the column opens rather
    /// than on every redraw (reading Settings decodes many defaults keys).
    private var shortcutCache: [ToolbarTool: String] = [:]

    private func refreshShortcuts() {
        var cache: [ToolbarTool: String] = [:]
        for tool in ToolbarTool.allCases {
            if let text = readShortcut(for: tool) { cache[tool] = text }
        }
        shortcutCache = cache
    }

    func shortcut(for tool: ToolbarTool) -> String? { shortcutCache[tool] }

    /// The tool's current global shortcut, read from Settings, e.g. "⌃4".
    private func readShortcut(for tool: ToolbarTool) -> String? {
        let app = UserDefaultsSettingsStore().load()
        func text(_ code: Int, _ modifiers: UInt) -> String? {
            code == 0 ? nil : HotkeyConflicts.displayString(keyCode: code, modifiers: modifiers)
        }
        switch tool {
        case .keystrokes: return text(teaching.keystrokes.settings.toggleKeyCode, teaching.keystrokes.settings.toggleModifiers)
        case .spotlight: return text(teaching.spotlight.settings.toggleKeyCode, teaching.spotlight.settings.toggleModifiers)
        case .captions: return text(teaching.captions.settings.toggleKeyCode, teaching.captions.settings.toggleModifiers)
        case .zoom: return text(app.hotKeyCode, app.hotKeyModifiers)
        case .draw: return text(app.drawHotKeyCode, app.drawHotKeyModifiers)
        case .breakTimer: return "⌃⇧T"
        case .screenshot: return text(app.snipHotKeyCode, app.snipHotKeyModifiers)
        case .record: return text(app.recordHotKeyCode, app.recordHotKeyModifiers)
        case .whiteboard: return "⌃⇧W"
        case .courseModes: return nil
        }
    }

    /// Tooltip text: the name plus its shortcut, so teachers learn them.
    func help(for tool: ToolbarTool, state: String? = nil) -> String {
        var text = tool.title
        if let state { text += "（\(state)）" }
        if let shortcut = shortcut(for: tool) { text += "  \(shortcut)" }
        return text
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
            stateTimer?.invalidate()
            stateTimer = nil
            return
        }
        let panel = self.panel ?? makePanel()
        let saved = UserDefaults.standard.dictionary(forKey: Self.positionKey)
        if let x = saved?["x"] as? Double, let y = saved?["y"] as? Double {
            place(at: NSPoint(x: x, y: y))
        } else if let bounds = NSScreen.main?.visibleFrame {
            place(at: GraphicalToolsLayout.defaultOrigin(in: bounds, scale: size.scale))
        }
        refreshState()
        panel.orderFrontRegardless()
        startStateTimer()
        scheduleIdle()
    }

    private func startStateTimer() {
        guard stateTimer == nil else { return }
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshState() }
        }
        RunLoop.main.add(timer, forMode: .common)
        stateTimer = timer
    }

    private func makePanel() -> ToolsPanel {
        let window = ToolsPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        // Above the spotlight's dimming (screenSaver - 1), so the button that
        // turns it off is never darkened. Hidden during zoom, draw and breaks.
        window.level = .screenSaver
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
        let scale = size.scale
        let clamped = GraphicalToolsLayout.clampedOrigin(origin, in: bounds, scale: scale)
        // Open: exactly as tall as the column needs, so there is no empty glass.
        let height = panelTall
            ? GraphicalToolsLayout.expandedHeight(originY: clamped.y, in: bounds, items: columnItems, scale: scale)
            : GraphicalToolsLayout.collapsedHeight(scale: scale)
        panel.setFrame(NSRect(x: clamped.x, y: clamped.y, width: GraphicalToolsLayout.width(scale: scale),
                              height: height),
                       display: true)
    }

    // MARK: Idle fade

    fileprivate func pointerInside(_ inside: Bool) {
        if inside {
            idleTask?.cancel()
            if idle { withAnimation(.easeOut(duration: 0.2)) { idle = false } }
        } else {
            scheduleIdle()
        }
    }

    private func scheduleIdle() {
        idleTask?.cancel()
        idleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.idleDelay * 1_000_000_000))
            guard !Task.isCancelled, let self, !self.expanded else { return }
            withAnimation(.easeInOut(duration: 0.6)) { self.idle = true }
        }
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
        refreshShortcuts()
        idleTask?.cancel()
        idle = false
        // Grow the window first so the column has room to animate into.
        panelTall = true
        place(at: panel.frame.origin)
        withAnimation(Self.openAnimation) { expanded = true }
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
        withAnimation(.easeIn(duration: Self.closeDuration)) { expanded = false }
        scheduleIdle()
        // Shrink the window once the column has finished leaving, unless it was
        // opened again meanwhile.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeDuration) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.expanded, self.panelTall else { return }
                self.panelTall = false
                if let panel = self.panel { self.place(at: panel.frame.origin) }
            }
        }
    }

    // MARK: Commands and live state

    fileprivate func run(_ command: AppCommand) {
        collapse()
        teaching.run(command)
        scheduleRefresh()
    }

    fileprivate func collapseForMenu() {
        collapse()
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
        var active: Set<ToolbarTool> = []
        if teaching.keystrokes.isActive { active.insert(.keystrokes) }
        if teaching.spotlight.spotlightOn { active.insert(.spotlight) }
        if teaching.captions.isRunning { active.insert(.captions) }
        if teaching.whiteboard.isVisible { active.insert(.whiteboard) }
        if recording { active.insert(.record) }
        if active != activeTools { activeTools = active }
        let modeID = teaching.courseModes.currentModeID
        if modeID != currentCourseModeID { currentCourseModeID = modeID }
    }

    fileprivate var courseModes: [CourseMode] { teaching.courseModes.allModes }
}

// MARK: - Views

private struct GraphicalToolsView: View {
    @ObservedObject var tools: GraphicalTools
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 5) {
            if tools.expanded {
                column
                    .transition(reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.92, anchor: .bottom)))
            }
            launcher
                .frame(height: 50 * tools.size.scale)
                .opacity(tools.idle && !tools.expanded ? 0.4 : 1)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { _ in tools.moveLauncher() }
                        .onEnded { _ in tools.finishMovingLauncher() }
                )
        }
        .padding(3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .environment(\.chromeIconScale, tools.size.scale)
        .contentShape(Rectangle())
        .onHover { tools.pointerInside($0) }
        .onExitCommand { tools.collapse() }
    }

    // MARK: Column

    private var column: some View {
        // Never taller than its content: no empty glass above the icons.
        let content = GraphicalToolsLayout.columnHeight(items: tools.pinned.count + 1, scale: tools.size.scale)
        return list
            .frame(maxHeight: content)
            .chromeSurface(RoundedRectangle(cornerRadius: 23 * tools.size.scale, style: .continuous))
    }

    /// Top to bottom: More, then the pinned tools reading down toward the
    /// launcher, then the "students can't see this" marker. Icons arrive from
    /// the launcher upward.
    private var list: some View {
        let pinned = tools.pinnedInOrder
        return ScrollView {
            VStack(spacing: GraphicalToolsLayout.rowSpacing) {
                moreMenu.staggered(pinned.count + 1)
                ForEach(Array(pinned.reversed().enumerated()), id: \.element) { index, tool in
                    toolView(tool).staggered(pinned.count - index)
                }
                Image(systemName: "eye.slash")
                    .font(.system(size: 12 * tools.size.scale, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: GraphicalToolsLayout.markerHeight * tools.size.scale)
                    .contentShape(Rectangle())
                    .help(L10n.t("Students can't see this toolbar: it is left out of shared screens and recordings.",
                                 "學生看不到這個工具列：分享畫面與錄影都不會擷取到它。"))
                    .accessibilityLabel(L10n.t("Hidden from students", "學生看不到"))
                    .staggered(0)
            }
            .padding(.vertical, GraphicalToolsLayout.columnPadding / 2)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func toolView(_ tool: ToolbarTool) -> some View {
        switch tool {
        case .courseModes:
            menu(tool) { courseModeItems }
        case .keystrokes:
            toggleButton(tool, .toggleKeystrokes)
        case .spotlight:
            toggleButton(tool, .toggleSpotlight)
        case .captions:
            toggleButton(tool, .toggleCaptions)
        case .whiteboard:
            toggleButton(tool, .toggleWhiteboard)
        case .draw:
            actionButton(tool, .activateDrawWithoutZoom)
        case .breakTimer:
            menu(tool) { timerItems }
        case .zoom:
            menu(tool) { zoomItems }
        case .screenshot:
            menu(tool) { screenshotItems }
        case .record:
            if tools.recording {
                Button { tools.run(.toggleRecording(region: false)) } label: { Image(systemName: "stop.circle.fill") }
                    .buttonStyle(ChromeIconButtonStyle(isOn: true, tint: .red))
                    .help(L10n.t("Stop Recording", "停止錄影"))
                    .accessibilityLabel(L10n.t("Stop Recording", "停止錄影"))
            } else {
                menu(tool) { recordItems }
            }
        }
    }

    // MARK: Menu contents (shared by pinned icons and "More")

    @ViewBuilder private var courseModeItems: some View {
        ForEach(tools.courseModes) { mode in
            Button {
                tools.apply(mode)
            } label: {
                Label(mode.name, systemImage: mode.id == tools.currentCourseModeID ? "checkmark" : mode.symbol)
            }
        }
    }

    @ViewBuilder private var timerItems: some View {
        ForEach(ClassCountdown.presets, id: \.self) { minutes in
            Button {
                tools.collapseForMenu()
                ClassCountdown.shared.start(minutes: minutes)
            } label: {
                Label(L10n.t("Countdown \(minutes) min", "課堂倒數 \(minutes) 分鐘"), systemImage: "timer")
            }
        }
        Divider()
        item(L10n.t("Full-Screen Break", "全螢幕休息"), "cup.and.saucer", .toggleBreakTimer)
    }

    @ViewBuilder private var zoomItems: some View {
        item(L10n.t("Static Zoom", "靜態放大"), "plus.magnifyingglass", .activateStaticZoom)
        item(L10n.t("Live Zoom", "即時放大"), "dot.viewfinder", .activateLiveZoom)
    }

    @ViewBuilder private var screenshotItems: some View {
        item(L10n.t("Copy Region", "複製區域"), "doc.on.clipboard", .snipRegion(save: false))
        item(L10n.t("Save Region", "儲存區域"), "square.and.arrow.down", .snipRegion(save: true))
    }

    @ViewBuilder private var recordItems: some View {
        item(L10n.t("Entire Screen", "全螢幕"), "display", .toggleRecording(region: false))
        item(L10n.t("Region", "區域"), "rectangle.dashed", .toggleRecording(region: true))
    }

    /// An unpinned tool as a "More" entry.
    @ViewBuilder
    private func moreEntry(_ tool: ToolbarTool) -> some View {
        switch tool {
        case .courseModes:
            Menu { courseModeItems } label: { Label(tool.title, systemImage: tool.symbol) }
        case .zoom:
            Menu { zoomItems } label: { Label(tool.title, systemImage: tool.symbol) }
        case .screenshot:
            Menu { screenshotItems } label: { Label(tool.title, systemImage: tool.symbol) }
        case .record:
            if tools.recording {
                item(L10n.t("Stop Recording", "停止錄影"), "stop.circle.fill", .toggleRecording(region: false))
            } else {
                Menu { recordItems } label: { Label(tool.title, systemImage: tool.symbol) }
            }
        case .keystrokes: item(tool.title, tool.symbol, .toggleKeystrokes)
        case .spotlight: item(tool.title, tool.symbol, .toggleSpotlight)
        case .captions: item(tool.title, tool.symbol, .toggleCaptions)
        case .whiteboard: item(tool.title, tool.symbol, .toggleWhiteboard)
        case .draw: item(tool.title, tool.symbol, .activateDrawWithoutZoom)
        case .breakTimer:
            Menu { timerItems } label: { Label(tool.title, systemImage: tool.symbol) }
        }
    }

    private var moreMenu: some View {
        Menu {
            if !tools.unpinned.isEmpty {
                Section(L10n.t("Other tools", "其他工具")) {
                    ForEach(tools.unpinned) { tool in moreEntry(tool) }
                }
            }
            Section(L10n.t("Capture and demo", "擷取與示範")) {
                item(L10n.t("Recognize Text", "辨識文字"), "text.viewfinder", .snipOcr)
                item(L10n.t("Copy Panorama", "複製長截圖"), "rectangle.split.1x2", .startPanorama(save: false))
                item(L10n.t("Save Panorama", "儲存長截圖"), "square.and.arrow.down", .startPanorama(save: true))
                #if !TEACHLENS_APP_STORE
                item(L10n.t("Auto Typing (DemoType)", "自動打字（DemoType）"), "keyboard", .startDemoType)
                #endif
                item(L10n.t("Mirror Window (DemoMirror)", "鏡像視窗（DemoMirror）"), "rectangle.on.rectangle",
                     .toggleDemoMirror(scope: .screen))
            }
            Menu {
                ForEach(ToolbarTool.allCases) { tool in
                    Button {
                        tools.togglePinned(tool)
                    } label: {
                        Label(tool.title, systemImage: tools.pinned.contains(tool) ? "checkmark" : tool.symbol)
                    }
                }
                Divider()
                Section(L10n.t("Button size", "按鈕大小")) {
                    ForEach(ToolbarSize.allCases) { option in
                        Button { tools.setSize(option) } label: {
                            Label(option.title, systemImage: option == tools.size ? "checkmark" : "textformat.size")
                        }
                    }
                }
                Divider()
                Button { tools.resetPinned() } label: {
                    Label(L10n.t("Back to the default six", "回復預設六項"), systemImage: "arrow.counterclockwise")
                }
            } label: {
                Label(L10n.t("Customize Toolbar", "自訂工具列"), systemImage: "slider.horizontal.3")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .chromeIconMenu()
        .help(L10n.t("More tools", "更多工具"))
        .accessibilityLabel(L10n.t("More tools", "更多工具"))
    }

    // MARK: Building blocks

    private func toggleButton(_ tool: ToolbarTool, _ command: AppCommand) -> some View {
        let on = tools.activeTools.contains(tool)
        let state = on ? L10n.t("On", "開啟") : L10n.t("Off", "關閉")
        return Button { tools.run(command) } label: { Image(systemName: tool.symbol) }
            .buttonStyle(ChromeIconButtonStyle(isOn: on))
            .help(tools.help(for: tool, state: state))
            .accessibilityLabel(tool.title)
            .accessibilityValue(state)
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func actionButton(_ tool: ToolbarTool, _ command: AppCommand) -> some View {
        Button { tools.run(command) } label: { Image(systemName: tool.symbol) }
            .buttonStyle(ChromeIconButtonStyle())
            .help(tools.help(for: tool))
            .accessibilityLabel(tool.title)
    }

    private func menu<Content: View>(_ tool: ToolbarTool, @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            Image(systemName: tool.symbol)
        }
        .chromeIconMenu()
        .help(tools.help(for: tool))
        .accessibilityLabel(tool.title)
    }

    private func item(_ title: String, _ systemName: String, _ command: AppCommand) -> some View {
        Button { tools.run(command) } label: { Label(title, systemImage: systemName) }
    }

    // MARK: Launcher

    /// Up to four status dots under the launcher glyph, one per tool that is on.
    private var statusDots: some View {
        let on = ToolbarTool.allCases.filter { tools.activeTools.contains($0) }.prefix(4)
        return HStack(spacing: 3) {
            ForEach(Array(on)) { tool in
                Circle().fill(tool.dotColor).frame(width: 4, height: 4)
            }
        }
        .animation(.easeOut(duration: 0.2), value: tools.activeTools)
    }

    @ViewBuilder private var launcher: some View {
        let title = tools.expanded
            ? L10n.t("Collapse Tools", "收合教學工具")
            : L10n.t("Expand Tools", "展開教學工具")
        let symbol = tools.expanded ? "chevron.down" : (tools.recording ? "record.circle.fill" : "square.grid.2x2")
        let onNames = ToolbarTool.allCases.filter { tools.activeTools.contains($0) }.map(\.title)
        let control = Button { tools.toggleExpanded() } label: {
            Image(systemName: symbol)
                .font(.system(size: 16 * tools.size.scale, weight: .semibold))
                .foregroundStyle(tools.recording && !tools.expanded ? Color.red : Color.primary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36 * tools.size.scale, height: 36 * tools.size.scale)
                .overlay(alignment: .bottom) {
                    if !tools.expanded { statusDots.offset(y: -3) }
                }
                .contentShape(Circle())
        }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(onNames.isEmpty ? "" : L10n.t("On: ", "開啟中：") + onNames.joined(separator: L10n.t(", ", "、")))
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            control.buttonStyle(.glass).buttonBorderShape(.circle)
        } else {
            control.buttonStyle(.plain).chromeSurface(Circle())
        }
        #else
        control.buttonStyle(.plain).chromeSurface(Circle())
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
