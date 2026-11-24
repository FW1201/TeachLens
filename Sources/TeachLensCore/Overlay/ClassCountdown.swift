import AppKit
import SwiftUI

/// "課堂倒數": a small Liquid Glass countdown in the top-right corner of the
/// shared screen, for activities such as a three-minute discussion. Unlike
/// the full-screen break timer it covers nothing; students see it. When time
/// is up it turns red, plays a sound, and leaves after a few seconds.
@MainActor
final class ClassCountdown {
    static let shared = ClassCountdown()
    static let presets: [Int] = [1, 3, 5]
    private static let lastKey = "classCountdownMinutes"

    private let model = CountdownModel()
    private var panel: NSPanel?
    private var timer: Timer?
    private var endTime: Date?

    var isRunning: Bool { endTime != nil }

    /// Control+Shift+T: start with the last length, or stop.
    func toggle() {
        if isRunning {
            stop()
        } else {
            let saved = UserDefaults.standard.integer(forKey: Self.lastKey)
            start(minutes: saved > 0 ? saved : 3)
        }
    }

    func start(minutes: Int) {
        UserDefaults.standard.set(minutes, forKey: Self.lastKey)
        endTime = Date().addingTimeInterval(TimeInterval(minutes * 60))
        model.finished = false
        update()
        show()
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        endTime = nil
        withAnimation(.easeIn(duration: 0.2)) { model.visible = false }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !self.isRunning else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func update() {
        guard let endTime else { return }
        let remaining = max(0, Int(ceil(endTime.timeIntervalSinceNow)))
        model.remaining = remaining
        if remaining == 0, !model.finished {
            model.finished = true
            NSSound(named: "Glass")?.play()
            timer?.invalidate()
            timer = nil
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, self.model.finished else { return }
                self.stop()
            }
        }
    }

    private func show() {
        let panel = self.panel ?? makePanel()
        let size = NSSize(width: 190, height: 84)
        if let screen = PresentationDisplay.screen() {
            let visible = screen.visibleFrame
            panel.setFrame(NSRect(x: visible.maxX - size.width - 16, y: visible.maxY - size.height - 16,
                                  width: size.width, height: size.height), display: true)
        }
        panel.orderFrontRegardless()
        withAnimation(TeachLensChrome.reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) {
            model.visible = true
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        // Students should see the countdown in shared screens and recordings.
        panel.sharingType = .readOnly
        panel.contentView = NSHostingView(rootView: CountdownView(model: model) { [weak self] in self?.stop() })
        self.panel = panel
        return panel
    }
}

@MainActor
final class CountdownModel: ObservableObject {
    @Published var remaining = 0
    @Published var finished = false
    @Published var visible = false
}

private struct CountdownView: View {
    @ObservedObject var model: CountdownModel
    let stop: () -> Void

    private var text: String {
        String(format: "%d:%02d", model.remaining / 60, model.remaining % 60)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.finished ? "bell.fill" : "timer")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(model.finished ? Color.red : Color.accentColor)
                .symbolEffect(.bounce, value: model.finished)
            VStack(alignment: .leading, spacing: 0) {
                Text(model.finished ? L10n.t("Time's up", "時間到") : text)
                    .font(.system(size: model.finished ? 22 : 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .foregroundStyle(model.finished ? Color.red : Color.primary)
                Text(L10n.t("Class countdown", "課堂倒數"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: stop) { Image(systemName: "xmark") }
                .buttonStyle(ChromeIconButtonStyle())
                .help(L10n.t("Stop (⌃⇧T)", "停止（⌃⇧T）"))
                .accessibilityLabel(L10n.t("Stop countdown", "停止倒數"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .chromeSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(6)
        .opacity(model.visible ? 1 : 0)
        .scaleEffect(model.visible ? 1 : 0.92, anchor: .topTrailing)
        .animation(.easeOut(duration: 0.2), value: model.remaining)
        .accessibilityElement(children: .combine)
    }
}
