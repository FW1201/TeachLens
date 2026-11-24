import AppKit
import SwiftUI

/// The first-launch guide: three short steps instead of a 17-pane Settings
/// window. 1) Which system do the students use? 2) Permissions, each with its
/// purpose. 3) Press ⌘C (or play the demo) and see the pill. Finishing turns
/// on the floating toolbar.
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    /// Set by the app delegate so Check & Test can reopen the guide.
    static weak var shared: OnboardingController?

    private let teaching: TeachingControllers
    private var window: NSWindow?
    var onFinish: (() -> Void)?

    init(teaching: TeachingControllers) {
        self.teaching = teaching
        super.init()
    }

    func show() {
        if window == nil {
            let view = OnboardingView(teaching: teaching, testCenter: teaching.testCenter,
                                      keystrokes: teaching.keystrokes.observableModel) { [weak self] in
                self?.finish()
            }
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
                                  styleMask: [.titled, .closable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: view)
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        window?.close()
        onFinish?()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

private struct OnboardingView: View {
    let teaching: TeachingControllers
    @ObservedObject var testCenter: TestCenter
    @ObservedObject var keystrokes: KeystrokeOverlayModel
    let finish: () -> Void

    @State private var step = 0
    @State private var platform: KeystrokePlatform = .mac
    @State private var sawPill = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let steps = 3

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch step {
                case 0: platformStep
                case 1: permissionStep
                default: tryStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 32)
            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                               removal: .move(edge: .leading).combined(with: .opacity)))
            .id(step)
            footer
        }
        .frame(width: 560, height: 470)
        .onAppear { platform = teaching.keystrokes.settings.primaryPlatform }
        .onChange(of: keystrokes.groups) { _, groups in
            if step == 2, !groups.isEmpty { withAnimation { sawPill = true } }
        }
    }

    // MARK: Header / footer

    private var header: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            Text(L10n.t("Welcome to TeachLens", "歡迎使用 TeachLens"))
                .font(.system(size: 22, weight: .bold, design: .rounded))
            HStack(spacing: 6) {
                ForEach(0..<steps, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Color.accentColor : Color.primary.opacity(0.15))
                        .frame(width: index == step ? 22 : 8, height: 8)
                }
            }
            .animation(.easeOut(duration: 0.2), value: step)
            .accessibilityLabel(L10n.t("Step \(step + 1) of \(steps)", "第 \(step + 1) 步，共 \(steps) 步"))
        }
        .padding(.top, 34)
        .padding(.bottom, 18)
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button { go(step - 1) } label: { Label(L10n.t("Back", "上一步"), systemImage: "chevron.left") }
                    .buttonStyle(.bordered)
            }
            Spacer()
            if step < steps - 1 {
                Button { go(step + 1) } label: { Label(L10n.t("Continue", "下一步"), systemImage: "chevron.right") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(action: finish) { Label(L10n.t("Start Using TeachLens", "開始使用"), systemImage: "checkmark") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
        .padding(20)
    }

    private func go(_ newStep: Int) {
        if step == 0 { savePlatform() }
        if newStep == 1 { testCenter.refreshPermissions() }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.9)) {
            step = newStep
        }
    }

    private func savePlatform() {
        teaching.keystrokes.update {
            $0.primaryPlatform = platform
            // Teachers of Windows students also see the Mac shortcut below.
            if platform == .windows { $0.windowsEquivalent = true }
        }
    }

    // MARK: Step 1

    private var platformStep: some View {
        VStack(spacing: 16) {
            Text(L10n.t("Which computers do your students use?", "你的學生主要使用哪種電腦？"))
                .font(.headline)
            HStack(spacing: 14) {
                platformCard(.mac, symbol: "laptopcomputer", example: "⌘C")
                platformCard(.windows, symbol: "pc", example: "Ctrl + C")
            }
            Text(L10n.t("Keystrokes show this system's shortcuts. You can change it any time.",
                        "按鍵顯示會以這個系統的快捷鍵為主，之後隨時可改。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func platformCard(_ value: KeystrokePlatform, symbol: String, example: String) -> some View {
        let selected = platform == value
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { platform = value }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 34, weight: .light))
                Text(value.shortTitle).font(.system(size: 16, weight: .semibold))
                Text(example)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            .frame(width: 190, height: 150)
            .chromeSurface(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: selected ? 2.5 : 0))
            .scaleEffect(selected ? 1.02 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Step 2

    private var permissionStep: some View {
        VStack(spacing: 10) {
            Text(L10n.t("Allow what TeachLens needs", "開啟 TeachLens 需要的權限"))
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(testCenter.permissions.filter { $0.id != "camera" }) { check in
                    HStack(spacing: 10) {
                        Image(systemName: check.state == .granted ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(check.state == .granted ? Color.green : Color.secondary)
                            .font(.system(size: 17))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(check.title).font(.system(size: 13, weight: .semibold))
                            Text(check.purpose).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if check.state != .granted {
                            Button { testCenter.fix(check) } label: {
                                Label(L10n.t("Allow…", "開啟…"), systemImage: "lock.open")
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                }
            }
            .chromeSurface(RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack {
                Text(L10n.t("Screen Recording and Input Monitoring take effect after reopening TeachLens.",
                            "螢幕錄製與輸入監控開啟後，需重新打開 TeachLens 才會生效。"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { testCenter.refreshPermissions() } label: {
                    Label(L10n.t("Refresh", "重新檢查"), systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: Step 3

    private var tryStep: some View {
        VStack(spacing: 16) {
            Text(L10n.t("Try it", "試試看"))
                .font(.headline)
            Image(systemName: sawPill ? "checkmark.circle.fill" : "command")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(sawPill ? Color.green : Color.accentColor)
                .contentTransition(.symbolEffect(.replace))
            Text(sawPill
                 ? L10n.t("You saw the pill — TeachLens is ready.", "看到膠囊了，TeachLens 已就緒。")
                 : L10n.t("Press ⌘C anywhere. A pill appears at the bottom of the screen.",
                          "在任何地方按一下 ⌘C，畫面下方會出現按鍵膠囊。"))
                .multilineTextAlignment(.center)
            Button {
                teaching.keystrokes.playDemo()
            } label: {
                Label(L10n.t("Play the demo instead", "改播放示範（不需權限）"), systemImage: "play.fill")
            }
            Text(L10n.t("Finishing turns on the floating toolbar at the bottom right. Start a class from the menu bar.",
                        "完成後，右下角會出現圖形工具列；上課時從選單列按「開始上課」。"))
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
