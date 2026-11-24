import AppKit
import SwiftUI

/// Settings ▸ 總覽與測試 / Check & Test: which build this is, whether the
/// permissions are in place, and a button to try each feature without its
/// shortcut, with a visible result.
struct CheckAndTestPane: View {
    let controllers: TeachingControllers
    @ObservedObject private var center: TestCenter
    @State private var results: [String: String] = [:]
    @State private var copied = false

    init(controllers: TeachingControllers) {
        self.controllers = controllers
        _center = ObservedObject(wrappedValue: controllers.testCenter)
    }

    var body: some View {
        Form {
            Section(L10n.t("This build", "這個版本")) {
                LabeledContent(L10n.t("Version", "版本"), value: "\(AppInfo.version) · \(AppInfo.commit)")
                LabeledContent(L10n.t("Build", "類型"), value: AppInfo.isDevBuild
                               ? L10n.t("Development (separate permissions)", "開發版（權限與正式版分開）")
                               : L10n.t("Release", "正式版"))
                Button(copied ? L10n.t("Copied", "已複製") : L10n.t("Copy diagnostics", "複製診斷資訊")) {
                    let text = center.diagnostics(keystrokes: controllers.keystrokes,
                                                  spotlight: controllers.spotlight,
                                                  captions: controllers.captions)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                }
            }

            Section(L10n.t("Before class: permissions", "課前檢查：權限")) {
                ForEach(center.permissions) { check in
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: check.state))
                            .foregroundStyle(color(for: check.state))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(check.title)
                            Text(check.purpose).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if check.state != .granted {
                            Button { center.fix(check) } label: { Label(L10n.t("Fix…", "修正…"), systemImage: "wrench.and.screwdriver") }
                        }
                    }
                }
                Text(L10n.t("After allowing Screen Recording or Input Monitoring, quit and reopen TeachLens.",
                            "開啟「螢幕錄製」或「輸入監控」後，請結束並重新打開 TeachLens。"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L10n.t("Try each feature (no shortcut needed)", "逐項測試（不用快捷鍵）")) {
                testRow("keys", L10n.t("Keystroke display demo", "按鍵顯示示範"),
                        L10n.t("Plays ⌘C, ⇧⌘4, ⌘Z ×3 on screen", "畫面播放 ⌘C、⇧⌘4、⌘Z ×3")) {
                    controllers.keystrokes.playDemo()
                }
                testRow("spot", L10n.t("Spotlight (5 seconds)", "聚光燈（5 秒）"), nil) {
                    let wasOn = controllers.spotlight.spotlightOn
                    controllers.spotlight.setSpotlight(true)
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        controllers.spotlight.setSpotlight(wasOn)
                    }
                }
                testRow("pulse", L10n.t("Find my cursor", "找游標光圈"), nil) {
                    controllers.spotlight.pulseNow()
                }
                testRow("caption", L10n.t("Sample caption", "字幕示範"),
                        L10n.t("No microphone needed", "不需要麥克風")) {
                    if !controllers.captions.showSample() {
                        results["caption"] = L10n.t("Stop live captions before the demo", "請先停止即時字幕再播放示範")
                    }
                }
                testRow("board", L10n.t("Open whiteboard", "打開白板"), nil) {
                    controllers.whiteboard.show()
                }
                testRow("zoom", L10n.t("Static zoom", "靜態放大"), L10n.t("Esc to exit", "按 Esc 離開")) {
                    controllers.run(.activateStaticZoom)
                }
                testRow("draw", L10n.t("Draw on screen", "畫筆"), L10n.t("Esc to exit", "按 Esc 離開")) {
                    controllers.run(.activateDrawWithoutZoom)
                }
                testRow("live", L10n.t("Live zoom", "即時放大"), L10n.t("Esc to exit", "按 Esc 離開")) {
                    controllers.run(.activateLiveZoom)
                }
                testRow("break", L10n.t("Break timer", "休息計時器"), L10n.t("Esc to exit", "按 Esc 離開")) {
                    controllers.run(.toggleBreakTimer)
                }
                testRow("snip", L10n.t("Snip a region", "截取區域"), L10n.t("Copies to the clipboard", "複製到剪貼簿")) {
                    controllers.run(.snipRegion(save: false))
                }
            }

            Section(L10n.t("Course modes", "課程模式")) {
                Text(L10n.t("Trying Break starts a timer. Exit it separately with Esc.",
                            "試用「休息」會啟動計時器；請另外按 Esc 結束計時。"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    ForEach(CourseMode.builtIns) { mode in
                        Button(mode.name) {
                            controllers.courseModes.saveRestorePoint()
                            controllers.courseModes.apply(mode)
                            results["modes"] = "✓ " + mode.name
                        }
                    }
                }
                HStack {
                    Button {
                        if controllers.courseModes.hasRestorePoint {
                            controllers.courseModes.restoreTestState()
                            results["modes"] = L10n.t("Restored", "已還原")
                        } else {
                            results["modes"] = L10n.t("No previous test setup", "沒有可還原的試用設定")
                        }
                    } label: {
                        Label(L10n.t("Restore previous setup", "回到原本設定"), systemImage: "arrow.uturn.backward")
                    }
                    if let result = results["modes"] {
                        Text(result).foregroundStyle(.green).font(.caption)
                    }
                }
            }

            Section(L10n.t("Shortcut check", "快捷鍵接收測試")) {
                Text(L10n.t("Press any TeachLens shortcut (for example ⌃0). If nothing appears here, the shortcut did not reach TeachLens.",
                            "按任一 TeachLens 快捷鍵（例如 ⌃0）。這裡沒有出現名稱，代表快捷鍵沒有送到 TeachLens。"))
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent(L10n.t("Last received", "最後收到")) {
                    if let name = center.lastShortcut, let at = center.lastShortcutAt {
                        Text("\(name) · \(at.formatted(date: .omitted, time: .standard))").foregroundStyle(.green)
                    } else {
                        Text(L10n.t("Nothing yet", "尚未收到")).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear { center.refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            center.refreshPermissions()
        }
    }

    private func testRow(_ id: String, _ title: String, _ note: String?, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if let result = results[id] {
                Text(result).font(.caption).foregroundStyle(.secondary)
            }
            Button {
                results[id] = nil
                action()
                // Dispatch is not proof that permissions were granted or that an
                // overlay appeared; invite the teacher to verify the result.
                if id != "caption" || results[id] != L10n.t("Stop live captions before the demo", "請先停止即時字幕再播放示範") {
                    results[id] = L10n.t("Requested — check the screen", "已送出操作，請確認畫面")
                }
            } label: {
                Label(L10n.t("Run", "立即測試"), systemImage: "play.fill")
            }
        }
    }

    private func icon(for state: PermissionCheck.State) -> String {
        switch state {
        case .granted: return "checkmark.circle.fill"
        case .missing: return "xmark.octagon.fill"
        case .notAsked: return "questionmark.circle"
        }
    }

    private func color(for state: PermissionCheck.State) -> Color {
        switch state {
        case .granted: return .green
        case .missing: return .red
        case .notAsked: return .orange
        }
    }
}
