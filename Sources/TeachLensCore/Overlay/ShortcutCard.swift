import AppKit
import SwiftUI

/// Hold Control on its own for a second to see every TeachLens shortcut on a
/// glass card; let go and it disappears. Nothing to memorise, no new button.
/// The card is for the teacher and is kept out of shared screens.
@MainActor
final class ShortcutCard {
    static let holdDelay: TimeInterval = 1.0

    private var panel: NSPanel?
    private var pending: Task<Void, Never>?

    /// Called by the keystroke listener: `controlAlone` is true while Control
    /// is the only key held.
    func controlHeld(alone: Bool) {
        if alone {
            guard pending == nil, panel?.isVisible != true else { return }
            pending = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.holdDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.show()
            }
        } else {
            pending?.cancel()
            pending = nil
            panel?.orderOut(nil)
        }
    }

    /// Display names for the registered shortcut list, in Chinese when chosen.
    static func title(for name: String) -> String {
        let names: [String: String] = [
            "Static Zoom": "靜態放大", "Draw": "畫筆", "Live Zoom": "即時放大", "Break Timer": "休息計時",
            "Snip": "截圖", "Snip to File": "截圖存檔", "OCR Snip": "辨識文字", "Record Screen": "錄製全螢幕",
            "Record Region": "錄製區域", "Panorama": "長截圖", "Panorama to File": "長截圖存檔",
            "DemoMirror": "鏡像視窗", "DemoMirror Region": "鏡像區域", "DemoMirror Window": "鏡像單一視窗",
            "DemoType": "自動打字", "DemoType Reset": "自動打字重設", "Show Keystrokes": "按鍵顯示",
            "Spotlight": "聚光燈", "Live Captions": "即時字幕", "Whiteboard": "白板",
            "Hide Overlays": "隱藏所有畫面提示", "Class Countdown": "課堂倒數",
        ]
        return L10n.isChinese ? (names[name] ?? name) : name
    }

    private func show() {
        pending = nil
        let shortcuts = HotkeyConflicts.registeredShortcuts(app: UserDefaultsSettingsStore().load())
            .map { (title: Self.title(for: $0.name),
                    keys: HotkeyConflicts.displayString(keyCode: $0.keyCode, modifiers: $0.modifiers)) }
        let hosting = NSHostingView(rootView: ShortcutCardView(shortcuts: shortcuts))
        let size = hosting.fittingSize
        let panel = self.panel ?? makePanel()
        panel.contentView = hosting
        if let screen = PresentationDisplay.screen() {
            let visible = screen.visibleFrame
            panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                                  width: size.width, height: size.height), display: true)
        }
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.sharingType = .none
        self.panel = panel
        return panel
    }
}

private struct ShortcutCardView: View {
    let shortcuts: [(title: String, keys: String)]

    var body: some View {
        let half = (shortcuts.count + 1) / 2
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.t("TeachLens shortcuts", "TeachLens 快捷鍵"), systemImage: "keyboard")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            HStack(alignment: .top, spacing: 28) {
                column(Array(shortcuts.prefix(half)))
                column(Array(shortcuts.dropFirst(half)))
            }
            Text(L10n.t("Release Control to close", "放開 Control 即關閉"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(22)
        .chromeSurface(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(16)
    }

    private func column(_ items: [(title: String, keys: String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.title).font(.system(size: 13))
                    Spacer(minLength: 16)
                    Text(item.keys)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                }
                .frame(width: 230)
            }
        }
    }
}
