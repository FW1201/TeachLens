import AppKit
import SwiftUI

/// The one notice style TeachLens uses for its own feedback (mode changes,
/// class start/end, exports, privacy pauses): a Liquid Glass capsule at the
/// top centre of the screen under the pointer that fades after a moment.
/// Notices are for the teacher, so they are kept out of screen captures and
/// shared screens.
@MainActor
final class GlassToast {
    static let shared = GlassToast()

    struct Action {
        let title: String
        let handler: @MainActor () -> Void
    }

    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private let model = GlassToastModel()

    /// Shows a notice. With an action the notice stays longer and takes clicks.
    func show(symbol: String, title: String, message: String? = nil, tint: Color = .accentColor,
              action: Action? = nil, duration: TimeInterval? = nil) {
        model.content = GlassToastContent(symbol: symbol, title: title, message: message, tint: tint,
                                          actionTitle: action?.title)
        model.action = { [weak self] in
            action?.handler()
            self?.hide()
        }
        let panel = self.panel ?? makePanel()
        panel.ignoresMouseEvents = action == nil
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? NSSize(width: 320, height: 64)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 12,
                                  width: size.width, height: size.height), display: true)
        }
        withAnimation(TeachLensChrome.reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) {
            model.visible = true
        }
        panel.orderFrontRegardless()

        hideTask?.cancel()
        let seconds = duration ?? (action == nil ? 2.0 : 5.0)
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        withAnimation(.easeIn(duration: 0.2)) { model.visible = false }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !self.model.visible else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 72),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.sharingType = .none
        panel.contentView = NSHostingView(rootView: GlassToastView(model: model))
        self.panel = panel
        return panel
    }
}

struct GlassToastContent: Equatable {
    var symbol: String
    var title: String
    var message: String?
    var tint: Color
    var actionTitle: String?
}

@MainActor
final class GlassToastModel: ObservableObject {
    @Published var content = GlassToastContent(symbol: "info.circle", title: "", message: nil, tint: .accentColor,
                                               actionTitle: nil)
    @Published var visible = false
    var action: @MainActor () -> Void = {}
}

private struct GlassToastView: View {
    @ObservedObject var model: GlassToastModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let content = model.content
        HStack(spacing: 12) {
            Image(systemName: content.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(content.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(content.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                if let message = content.message {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 300, alignment: .leading)
            if let actionTitle = content.actionTitle {
                Button(actionTitle) { model.action() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .chromeSurface(Capsule())
        .padding(14)
        .opacity(model.visible ? 1 : 0)
        .offset(y: model.visible || reduceMotion ? 0 : -10)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
