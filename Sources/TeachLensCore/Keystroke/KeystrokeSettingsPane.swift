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
                Toggle("Show keystrokes on screen", isOn: $draft.enabled)
                Picker("Show", selection: $draft.filter) {
                    Text("Shortcuts only").tag(KeystrokeFilter.modifiers)
                    Text("Every key").tag(KeystrokeFilter.none)
                }
                Toggle("Include mouse clicks in shortcuts", isOn: $draft.showMouseEvents)
                Toggle("Click ripples at the pointer", isOn: $draft.showClickRipples)
                Toggle("Keep recent shortcuts", isOn: $draft.showHistory)
                if draft.showHistory {
                    Stepper("Recent shortcuts: \(draft.maxHistory)", value: $draft.maxHistory, in: 2...6)
                }
            }
            Section {
                Picker("Position", selection: $draft.position) {
                    ForEach(KeystrokePosition.allCases, id: \.self) { position in
                        Text(position.title).tag(position)
                    }
                }
                Picker("Background", selection: $draft.glass) {
                    ForEach(KeystrokeGlass.allCases, id: \.self) { glass in
                        Text(glass.title).tag(glass)
                    }
                }
                LabeledContent("Size") {
                    Slider(value: $draft.scale, in: 0.5...3, step: 0.25)
                        .frame(width: 180)
                }
                LabeledContent("Stay on screen") {
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
                LabeledContent("Show/hide shortcut") {
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
                    ignoring: "Show Keystrokes"
                ) {
                    Label("Also used by \(conflict). Pick another shortcut.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                LabeledContent("Input Monitoring") {
                    HStack {
                        Label(permissionGranted ? "Allowed" : "Not allowed",
                              systemImage: permissionGranted ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(permissionGranted ? .green : .red)
                        if !permissionGranted {
                            Button("Open Settings…") {
                                InputMonitoringPermission.request()
                                InputMonitoringPermission.openSettings()
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
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
