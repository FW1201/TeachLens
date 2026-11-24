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
                Toggle("Spotlight around the pointer", isOn: $spotlightOn)
                Picker("Shape", selection: $draft.shape) {
                    ForEach(SpotlightShape.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                LabeledContent("Size") {
                    Slider(value: $draft.radius, in: SpotlightSettings.radiusRange, step: 10)
                        .frame(width: 200)
                }
                LabeledContent("Dimming") {
                    Slider(value: $draft.dimming, in: SpotlightSettings.dimmingRange, step: 0.05)
                        .frame(width: 200)
                }
                LabeledContent("Shortcut") {
                    Button(recorder.isRecording
                           ? "Press a shortcut…"
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
                    Label("Also used by \(conflict). Pick another shortcut.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            Section {
                Toggle("Cursor highlight ring", isOn: $draft.highlightEnabled)
                Picker("Ring color", selection: $draft.highlightColor) {
                    ForEach(HighlightColor.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                LabeledContent("Ring size") {
                    Slider(value: $draft.highlightDiameter, in: 30...120, step: 2)
                        .frame(width: 200)
                }
                Toggle("Shake the mouse to find the cursor", isOn: $draft.shakeToFind)
            }
        }
        .formStyle(.grouped)
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
