import SwiftUI

/// The "Spotlight" pane in Settings (standard SwiftUI controls).
struct SpotlightSettingsPane: View {
    let controller: SpotlightController
    let loadAppSettings: () -> AppSettings

    @State private var draft = SpotlightSettings()
    @State private var spotlightOn = false
    @State private var didLoad = false
    @StateObject private var recorder = ShortcutRecorder()

    var body: some View {
        Form {
            Section {
                Toggle(L10n.t("Spotlight around the pointer", "游標聚光燈"), isOn: $spotlightOn)
                Picker(L10n.t("Shape", "形狀"), selection: $draft.shape) {
                    ForEach(SpotlightShape.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                LabeledContent(L10n.t("Size", "大小")) {
                    Slider(value: $draft.radius, in: SpotlightSettings.radiusRange, step: 10)
                        .frame(width: 200)
                }
                LabeledContent(L10n.t("Dimming", "暗度")) {
                    Slider(value: $draft.dimming, in: SpotlightSettings.dimmingRange, step: 0.05)
                        .frame(width: 200)
                }
                LabeledContent(L10n.t("Shortcut", "快捷鍵")) {
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
                    ignoring: "Spotlight"
                ) {
                    Label(L10n.t("Also used by \(conflict). Pick another shortcut.", "已被「\(conflict)」使用，請換一組。"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            Section {
                Toggle(L10n.t("Cursor highlight ring", "游標光圈"), isOn: $draft.highlightEnabled)
                Picker(L10n.t("Ring color", "光圈顏色"), selection: $draft.highlightColor) {
                    ForEach(HighlightColor.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                LabeledContent(L10n.t("Ring size", "光圈大小")) {
                    Slider(value: $draft.highlightDiameter, in: 30...120, step: 2)
                        .frame(width: 200)
                }
                Toggle(L10n.t("Shake the mouse to find the cursor", "搖動滑鼠找游標"), isOn: $draft.shakeToFind)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            if !didLoad {
                draft = controller.settings
                spotlightOn = controller.spotlightOn
                didLoad = true
            }
        }
        .onDisappear { recorder.stop() }
        .onChange(of: draft) { _, newValue in
            guard didLoad else { return }
            controller.update { $0 = newValue }
        }
        .onChange(of: spotlightOn) { _, newValue in
            guard didLoad else { return }
            controller.setSpotlight(newValue)
        }
    }
}
