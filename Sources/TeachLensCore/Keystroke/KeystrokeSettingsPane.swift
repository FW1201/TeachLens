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
    @StateObject private var customRecorder = KeyComboRecorder()
    @State private var permissionGranted = InputMonitoringPermission.isGranted
    @State private var presentationDisplay: CGDirectDisplayID = PresentationDisplay.selectedID

    var body: some View {
        Form {
            Section {
                Toggle(L10n.t("Show keystrokes on screen", "在畫面上顯示按鍵"), isOn: $draft.enabled)
                Picker(L10n.t("Show", "顯示"), selection: $draft.filter) {
                    Text(L10n.t("Shortcuts only", "只顯示快捷鍵")).tag(KeystrokeFilter.modifiers)
                    Text(L10n.t("Every key", "每個鍵")).tag(KeystrokeFilter.none)
                }
                Toggle(L10n.t("Include mouse clicks in shortcuts", "快捷鍵包含滑鼠點擊"), isOn: $draft.showMouseEvents)
                Toggle(isOn: $draft.showClickRipples) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.t("Click ripples at the pointer", "點擊時顯示漣漪"))
                        if !draft.enabled {
                            Text(L10n.t("Turn on “Show keystrokes on screen” first.", "需先開啟「在畫面上顯示按鍵」。"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(!draft.enabled)
                Picker(selection: $draft.primaryPlatform) {
                    ForEach(KeystrokePlatform.allCases, id: \.self) { platform in
                        Text(platform.shortTitle).tag(platform)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.t("Main shortcut", "主要顯示"))
                        Text(draft.primaryPlatform == .windows
                             ? L10n.t("The pill shows Ctrl + C for ⌘C, for classes on Windows.",
                                      "膠囊顯示 Ctrl + C 等 Windows 快捷鍵，適合學生用 Windows 的課堂。")
                             : L10n.t("The pill shows Mac shortcuts such as ⌘C.", "膠囊顯示 ⌘C 等 Mac 快捷鍵。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .pickerStyle(.segmented)
                Toggle(isOn: $draft.windowsEquivalent) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(draft.primaryPlatform == .windows
                             ? L10n.t("Also show the Mac shortcut below", "下方同時顯示 Mac 對照")
                             : L10n.t("Show Windows equivalents", "開啟 Windows 對照"))
                        Text(L10n.t("Suggested equivalents; the actual shortcut depends on the app.",
                                    "建議對照，實際快捷鍵依軟體而異。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button {
                    WindowsEquivalent.exportCheatSheet()
                } label: {
                    Label(L10n.t("Export Mac ↔ Windows handout (PDF)…", "匯出 Mac ↔ Windows 對照講義（PDF）…"),
                          systemImage: "doc.richtext")
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
                Picker(L10n.t("Size", "大小"), selection: $draft.scale) {
                    ForEach(KeystrokeSizePreset.allCases, id: \.self) { preset in
                        Text(preset.title).tag(preset.rawValue)
                    }
                    if KeystrokeSizePreset(rawValue: draft.scale) == nil {
                        Text(L10n.t("Custom ×\(String(format: "%.2g", draft.scale))",
                                    "自訂 ×\(String(format: "%.2g", draft.scale))")).tag(draft.scale)
                    }
                }
                Toggle(isOn: $draft.avoidMeetingBar) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.t("Keep clear of the video-call bar", "避開會議軟體控制列"))
                        Text(L10n.t("Bottom pills sit higher so Zoom, Meet and Teams controls don't cover them.",
                                    "下方的按鍵膠囊往上移，不會被 Zoom、Meet、Teams 的控制列擋住。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Picker(selection: $presentationDisplay) {
                    Text(L10n.t("Follow the pointer", "跟隨游標")).tag(CGDirectDisplayID(0))
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        if let id = PresentationDisplay.displayID(of: screen) {
                            Text(screen.localizedName).tag(id)
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.t("Shared screen", "分享中的螢幕"))
                        Text(L10n.t("Keystrokes and captions stay on the screen students see.",
                                    "按鍵與字幕固定顯示在學生看得到的螢幕。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onChange(of: presentationDisplay) { _, id in PresentationDisplay.selectedID = id }
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
                ForEach($draft.customShortcuts) { $entry in
                    HStack(spacing: 8) {
                        Text(entry.displayText)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .frame(minWidth: 64, alignment: .leading)
                        TextField(L10n.t("Caption", "說明"), text: $entry.label,
                                  prompt: Text(L10n.t("e.g. Brush tool", "例：筆刷工具")))
                            .labelsHidden()
                        TextField(L10n.t("Windows", "Windows 對照"), text: $entry.windows,
                                  prompt: Text(L10n.t("Windows (optional)", "Windows（選填）")))
                            .labelsHidden()
                            .frame(maxWidth: 130)
                        Button {
                            draft.customShortcuts.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.t("Remove", "移除"))
                    }
                }
                Button {
                    if customRecorder.isRecording {
                        customRecorder.stop()
                    } else {
                        customRecorder.start { keys in
                            if let index = draft.customShortcuts.firstIndex(where: { $0.keySet == Set(keys.map(CustomShortcut.normalized)) }) {
                                draft.customShortcuts[index].keys = keys
                            } else {
                                draft.customShortcuts.append(CustomShortcut(keys: keys))
                            }
                        }
                    }
                } label: {
                    Label(customRecorder.isRecording
                          ? L10n.t("Press the shortcut… (Esc cancels)", "請按下快捷鍵…（Esc 取消）")
                          : L10n.t("Add shortcut…", "新增快捷鍵…"),
                          systemImage: customRecorder.isRecording ? "keyboard" : "plus.circle")
                }
            } header: {
                Text(L10n.t("Custom shortcuts", "自訂快捷鍵"))
            } footer: {
                Text(L10n.t("Always shown, even single keys such as F5 or B, with your caption under the pill.",
                            "一律顯示（含 F5、B 等單鍵），並在膠囊下方顯示你寫的說明。"))
                    .font(.caption).foregroundStyle(.secondary)
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
        .onDisappear {
            recorder.stop()
            customRecorder.stop()
        }
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

/// Captures one key combination for a custom shortcut. Unlike
/// `ShortcutRecorder` it accepts keys without a modifier (F5, B).
@MainActor
final class KeyComboRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    private var monitor: Any?

    func start(onRecord: @escaping ([String]) -> Void) {
        stop()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = Int(event.keyCode)
            let flags = event.modifierFlags.rawValue
            MainActor.assumeIsolated {
                guard let self else { return }
                if keyCode == kVK_Escape {
                    self.stop()
                } else if let keys = Self.keys(keyCode: keyCode, flags: flags) {
                    onRecord(keys)
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

    /// Key names for a key press, modifiers first.
    nonisolated static func keys(keyCode: Int, flags: UInt) -> [String]? {
        guard let key = KeyCodeMap.name(for: keyCode), !KeyName.modifiers.contains(key) else { return nil }
        let modifierFlags = NSEvent.ModifierFlags(rawValue: flags)
        var names: [String] = []
        if modifierFlags.contains(.control) { names.append(KeyName.controlLeft) }
        if modifierFlags.contains(.option) { names.append(KeyName.alt) }
        if modifierFlags.contains(.shift) { names.append(KeyName.shiftLeft) }
        if modifierFlags.contains(.command) { names.append(KeyName.metaLeft) }
        names.append(key)
        return names
    }
}
