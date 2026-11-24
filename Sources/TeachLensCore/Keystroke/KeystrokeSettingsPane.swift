import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The "Keystrokes" pane in Settings. Built from standard SwiftUI controls so
/// it picks up the system look (Liquid Glass controls on macOS 26).
struct KeystrokeSettingsPane: View {
    @ObservedObject var model: KeystrokeOverlayModel
    let controller: KeystrokeController
    let loadAppSettings: () -> AppSettings

    @State private var draft = KeystrokeSettings()
    @State private var didLoad = false
    @StateObject private var recorder = ShortcutRecorder()
    @State private var permissionGranted = InputMonitoringPermission.isGranted

    var body: some View {
        Form {
            Section {
                Toggle(L10n.t("Show keystrokes on screen", "在畫面上顯示按鍵"), isOn: $draft.enabled)
                Picker(L10n.t("Show", "顯示"), selection: $draft.filter) {
                    Text(L10n.t("Shortcuts only", "只顯示快捷鍵")).tag(KeystrokeFilter.modifiers)
                    Text(L10n.t("Every key", "每個鍵")).tag(KeystrokeFilter.none)
                }
                Toggle(L10n.t("Include mouse clicks in shortcuts", "快捷鍵包含滑鼠點擊"), isOn: $draft.showMouseEvents)
                Toggle(L10n.t("Click ripples at the pointer", "點擊時顯示漣漪"), isOn: $draft.showClickRipples)
                Toggle(isOn: $draft.windowsEquivalent) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.t("Show Windows equivalents", "開啟 Windows 對照"))
                        Text(L10n.t("Suggested equivalents; the actual shortcut depends on the app.",
                                    "建議對照，實際快捷鍵依軟體而異。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(L10n.t("Keep recent shortcuts", "保留最近的快捷鍵"), isOn: $draft.showHistory)
                if draft.showHistory {
                    Stepper(L10n.t("Recent shortcuts: \(draft.maxHistory)", "最近快捷鍵：\(draft.maxHistory)"), value: $draft.maxHistory, in: 2...6)
                }
            }
            Section {
                Picker(L10n.t("Position", "位置"), selection: $draft.position) {
                    ForEach(KeystrokePosition.allCases, id: \.self) { position in
                        Text(position.title).tag(position)
                    }
                }
                Picker(L10n.t("Background", "背景"), selection: $draft.glass) {
                    ForEach(KeystrokeGlass.allCases, id: \.self) { glass in
                        Text(glass.title).tag(glass)
                    }
                }
                LabeledContent(L10n.t("Size", "大小")) {
                    Slider(value: $draft.scale, in: 0.5...3, step: 0.25)
                        .frame(width: 180)
                }
                LabeledContent(L10n.t("Stay on screen", "停留時間")) {
                    HStack {
                        Slider(value: $draft.lingerSeconds, in: 1...10, step: 0.5)
                            .frame(width: 140)
                        Text(String(format: "%.1f s", draft.lingerSeconds))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                LabeledContent(L10n.t("Show/hide shortcut", "開關快捷鍵")) {
                    Button(recorder.isRecording
                           ? L10n.t("Press a shortcut…", "請按快捷鍵…")
                           : HotkeyConflicts.displayString(keyCode: draft.toggleKeyCode, modifiers: draft.toggleModifiers)) {
                        if recorder.isRecording {
                            recorder.stop()
                        } else {
                            recorder.start { keyCode, modifiers in
                                draft.toggleKeyCode = keyCode
                                draft.toggleModifiers = modifiers
                            }
                        }
                    }
                }
                if let conflict = HotkeyConflicts.conflict(
                    keyCode: draft.toggleKeyCode,
                    modifiers: draft.toggleModifiers,
                    app: loadAppSettings(),
                    ignoring: "Show Keystrokes"
                ) {
                    Label(L10n.t("Also used by \(conflict). Pick another shortcut.", "已被「\(conflict)」使用，請換一組。"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                LabeledContent(L10n.t("Input Monitoring", "輸入監控")) {
                    HStack {
                        Label(permissionGranted ? L10n.t("Allowed", "已允許") : L10n.t("Not allowed", "未允許"),
                              systemImage: permissionGranted ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(permissionGranted ? .green : .red)
                        if !permissionGranted {
                            Button {
                                InputMonitoringPermission.request()
                                InputMonitoringPermission.openSettings()
                            } label: {
                                Label(L10n.t("Open Settings…", "打開系統設定…"), systemImage: "gearshape")
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            if !didLoad {
                draft = model.settings
                didLoad = true
            }
            permissionGranted = InputMonitoringPermission.isGranted
        }
        .onDisappear { recorder.stop() }
        .onReceive(model.$settings) { latest in
            if latest != draft { draft = latest }
        }
        .onChange(of: draft) { _, newValue in
            guard didLoad, newValue != model.settings else { return }
            if newValue.filter == .none && model.settings.filter != .none && !KeystrokeController.confirmEveryKey() {
                draft.filter = model.settings.filter
                return
            }
            controller.update { $0 = newValue }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionGranted = InputMonitoringPermission.isGranted
        }
    }
}

/// Captures the next key combination pressed in the Settings window.
@MainActor
final class ShortcutRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    private var monitor: Any?

    func start(onRecord: @escaping (Int, UInt) -> Void) {
        stop()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = Int(event.keyCode)
            let modifiers = event.modifierFlags.intersection(HotkeyConflicts.relevantModifiers).rawValue
            MainActor.assumeIsolated {
                guard let self else { return }
                if keyCode == kVK_Escape {
                    self.stop()
                } else if modifiers != 0 {
                    // Global shortcuts need at least one modifier.
                    onRecord(keyCode, modifiers)
                    self.stop()
                }
            }
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
    }
}
