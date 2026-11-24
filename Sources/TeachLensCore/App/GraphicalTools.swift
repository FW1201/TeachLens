import AppKit
import SwiftUI

@MainActor
final class GraphicalTools: ObservableObject {
    static let preference = "graphicalToolsEnabled"
    @Published private(set) var expanded = false
    @Published var recording = false
    private let teaching: TeachingControllers
    private var panel: ToolsPanel?

    init(teaching: TeachingControllers) {
        self.teaching = teaching
    }

    var windowNumber: Int? { panel?.windowNumber }

    func setVisible(_ visible: Bool) {
        guard visible else {
            expanded = false
            panel?.orderOut(nil)
            return
        }
        guard let screen = NSScreen.main else { return }
        if panel == nil {
            let window = ToolsPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: controls)
            window.onDismiss = { [weak self] in self?.collapse() }
            panel = window
        }
        let frame = screen.visibleFrame
        panel?.setFrame(NSRect(x: frame.maxX - 74, y: frame.minY + 16, width: 58, height: 56), display: true)
        panel?.orderFrontRegardless()
    }

    func toggleExpanded() {
        if expanded {
            collapse()
        } else {
            expanded = true
            resize()
            panel?.makeKey()
        }
    }

    private func collapse() {
        guard expanded else { return }
        expanded = false
        resize()
    }

    private func resize() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        var frame = panel.frame
        let height = expanded ? min(540, screen.visibleFrame.maxY - frame.minY) : 56
        frame.size.height = height
        panel.setFrame(frame, display: true)
    }

    private func run(_ command: AppCommand) {
        collapse()
        teaching.run(command)
    }

    private func label(_ title: String, _ icon: String) -> some View {
        Image(systemName: icon)
            .frame(width: 30, height: 28)
            .help(title)
            .accessibilityLabel(title)
    }

    private func button(_ title: String, _ icon: String, _ command: AppCommand) -> some View {
        Button { run(command) } label: { label(title, icon) }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
    }

    private func menu<Content: View>(_ title: String, _ icon: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        Menu(content: content) { label(title, icon) }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(title)
            .help(title)
    }

    private func item(_ title: String, _ command: AppCommand) -> some View {
        Button(title) { run(command) }
    }

    @ViewBuilder private var list: some View {
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
                if recording {
                    button(L10n.t("Stop Recording", "停止錄影"), "stop.circle.fill", .toggleRecording(region: false))
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
                button(L10n.t("Captions", "字幕"), "captions.bubble", .toggleCaptions)
                button(L10n.t("Whiteboard", "白板"), "rectangle.and.pencil.and.ellipsis", .toggleWhiteboard)
                button(L10n.t("Draw", "畫筆"), "pencil.tip", .activateDrawWithoutZoom)
                menu(L10n.t("Zoom", "放大"), "magnifyingglass") {
                    item(L10n.t("Static Zoom", "靜態放大"), .activateStaticZoom)
                    item(L10n.t("Live Zoom", "即時放大"), .activateLiveZoom)
                }
                button(L10n.t("Spotlight", "聚光燈"), "lightbulb", .toggleSpotlight)
                button(L10n.t("Keystrokes", "按鍵顯示"), "command", .toggleKeystrokes)
                menu(L10n.t("Course Modes", "課程模式"), "square.stack") {
                    ForEach(teaching.courseModes.allModes) { mode in
                        Button(mode.name) {
                            collapse()
                            teaching.courseModes.apply(mode)
                        }
                    }
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var controls: some View {
        GraphicalToolsView(tools: self)
    }

    fileprivate var bodyContent: some View {
        VStack(spacing: 5) {
            if expanded {
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
            launcher.frame(height: 50)
        }
        .padding(3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    @ViewBuilder private var launcher: some View {
        let title = expanded ? L10n.t("Collapse Tools", "收合教學工具") : L10n.t("Expand Tools", "展開教學工具")
        let control = Button(action: toggleExpanded) {
            Image(systemName: expanded ? "chevron.down" : "square.grid.2x2")
                .frame(width: 36, height: 36)
        }
        .accessibilityLabel(title)
        .help(title)
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

private struct GraphicalToolsView: View {
    @ObservedObject var tools: GraphicalTools

    var body: some View { tools.bodyContent }
}

private final class ToolsPanel: NSPanel {
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { onDismiss?() }

    override func resignKey() {
        super.resignKey()
        onDismiss?()
    }
}
