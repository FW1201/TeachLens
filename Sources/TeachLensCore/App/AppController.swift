import AppKit

@MainActor
final class AppController: NSObject {
    private let settingsStore: SettingsStore
    private let permissionService: PermissionService
    private let hotkeyService: HotkeyService
    private let modeCoordinator: ModeCoordinator
    private let userSelectedResourceAccess: UserSelectedResourceAccess
    let keystrokeController: KeystrokeController
    let spotlightController: SpotlightController
    let captionController: CaptionController
    /// One-shot observer used to re-present the permissions dialog when the user
    /// returns to TeachLens after being sent to System Settings.
    private var permissionReactivationObserver: NSObjectProtocol?
    private lazy var settingsWindowController = SettingsWindowController(
        settingsStore: settingsStore,
        onHotKeyChange: { [weak self] in self?.hotkeyService.reloadHotkey() },
        onSuspendHotkeys: { [weak self] in self?.hotkeyService.stop() },
        onResumeHotkeys: { [weak self] in self?.hotkeyService.start() },
        onRequestMicrophone: { [weak self] in self?.permissionService.requestMicrophoneAccess(completion: nil) },
        onRequestSpeechRecognition: { [weak self] in self?.requestSnipDictationPermissions() },
        onRequestCamera: { [weak self] in self?.permissionService.requestCameraAccess(completion: nil) },
        onOpenTrimEditor: { [weak self] in self?.modeCoordinator.openTrimEditor() },
        userSelectedResourceAccess: userSelectedResourceAccess,
        keystrokeController: keystrokeController,
        spotlightController: spotlightController
    )

    init(
        settingsStore: SettingsStore,
        permissionService: PermissionService,
        hotkeyService: HotkeyService,
        modeCoordinator: ModeCoordinator,
        userSelectedResourceAccess: UserSelectedResourceAccess,
        keystrokeController: KeystrokeController,
        spotlightController: SpotlightController,
        captionController: CaptionController
    ) {
        self.settingsStore = settingsStore
        self.permissionService = permissionService
        self.hotkeyService = hotkeyService
        self.modeCoordinator = modeCoordinator
        self.userSelectedResourceAccess = userSelectedResourceAccess
        self.keystrokeController = keystrokeController
        self.spotlightController = spotlightController
        self.captionController = captionController
        super.init()
    }

    @objc func activateStaticZoom() {
        modeCoordinator.handle(.activateStaticZoom)
    }

    @objc func activateDrawWithoutZoom() {
        modeCoordinator.handle(.activateDrawWithoutZoom)
    }

    @objc func activateLiveZoom() {
        modeCoordinator.handle(.activateLiveZoom)
    }

    @objc func toggleRecording() {
        modeCoordinator.handle(.toggleRecording(region: false))
    }

    @objc func startPanorama() {
        modeCoordinator.handle(.startPanorama(save: false))
    }

    @objc func toggleDemoMirror() {
        modeCoordinator.handle(.toggleDemoMirror(scope: .screen))
    }

    @objc func toggleBreakTimer() {
        modeCoordinator.handle(.toggleBreakTimer)
    }

    @objc func toggleKeystrokes() {
        keystrokeController.toggle()
    }

    @objc func toggleSpotlight() {
        spotlightController.toggleSpotlight()
    }

    @objc func toggleCaptions() {
        captionController.toggle()
    }

    /// Replaced by WhiteboardController.toggle when the menu is built.
    @objc func toggleWhiteboard() {}

    @objc func showSettings() {
        settingsWindowController.show()
    }

    @objc func checkPermissions() {
        presentPermissionsDialog()
    }

    /// Shows the permission status dialog and acts on the chosen button, then
    /// re-presents itself so the user can grant or open settings for several
    /// permissions in one sitting and watch the status refresh. For the
    /// microphone/Speech Recognition/camera grant prompts (which are
    /// asynchronous), it waits for the system prompt to resolve before
    /// re-presenting; other actions re-present on the next runloop turn. It
    /// stops only when the user clicks Done.
    private func presentPermissionsDialog() {
        let state = permissionService.currentState()
        let screenGranted = state.screenCapture.isGranted
        let micStatus = permissionService.microphoneStatus()
        let speechStatus = permissionService.speechRecognitionStatus()
        let camStatus = permissionService.cameraStatus()
        let inputMonitoringGranted = InputMonitoringPermission.isGranted
        func describe(_ status: MicrophonePermission) -> String {
            switch status {
            case .granted: return "Granted"
            case .denied: return "Denied"
            case .notDetermined: return "Not requested"
            }
        }
        func describe(_ status: SpeechRecognitionPermission) -> String {
            switch status {
            case .granted: return "Granted"
            case .denied: return "Denied"
            case .notDetermined: return "Not requested"
            }
        }

        let alert = NSAlert()
        alert.messageText = "TeachLens Permissions"
        alert.informativeText = """
        Screen Recording: \(screenGranted ? "Granted" : "Missing")
        Microphone: \(describe(micStatus))
        Speech Recognition: \(describe(speechStatus))
        Camera: \(describe(camStatus))
        Input Monitoring: \(inputMonitoringGranted ? "Granted" : "Missing")

        Screen Recording is required for zoom, snip, and recording. Microphone and Speech Recognition are optional for snip dictation; Camera is optional for recording. Input Monitoring is required to show keystrokes.

        Newly granted Screen Recording takes effect after you relaunch TeachLens.
        """
        alert.addButton(withTitle: "Done")
        alert.addButton(withTitle: screenGranted ? "Screen Recording Settings…" : "Grant Screen Recording…")
        alert.addButton(withTitle: micStatus == .notDetermined ? "Grant Microphone…" : "Microphone Settings…")
        alert.addButton(withTitle: speechStatus == .notDetermined ? "Grant Speech Recognition…" : "Speech Recognition Settings…")
        alert.addButton(withTitle: camStatus == .notDetermined ? "Grant Camera…" : "Camera Settings…")
        alert.addButton(withTitle: inputMonitoringGranted ? "Input Monitoring Settings…" : "Grant Input Monitoring…")
        // Use a standard macOS-style rounded-square icon so the dialog matches
        // the look of system permission prompts and the icon top lines up with
        // the message text.
        if let icon = TeachLensAppIcon.standardIcon() {
            alert.icon = icon
        }
        alert.window.animationBehavior = .none
        NSApp.activate(ignoringOtherApps: true)

        switch alert.runModal() {
        case .alertSecondButtonReturn:
            if screenGranted {
                permissionService.openSystemSettings()
                representWhenActive()
            } else {
                let granted = permissionService.requestScreenCaptureAccess()
                if granted {
                    presentPermissionsDialog()
                }
            }
        case .alertThirdButtonReturn:
            if micStatus == .notDetermined {
                // Wait for the system prompt to resolve, then re-present so the
                // dialog doesn't collide with it and shows the updated status.
                permissionService.requestMicrophoneAccess { [weak self] in
                    self?.presentPermissionsDialog()
                }
            } else {
                permissionService.openMicrophoneSettings()
                representWhenActive()
            }
        case NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + 1):
            if speechStatus == .notDetermined {
                permissionService.requestSpeechRecognitionAccess { [weak self] in
                    self?.presentPermissionsDialog()
                }
            } else {
                permissionService.openSpeechRecognitionSettings()
                representWhenActive()
            }
        case NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + 2):
            if camStatus == .notDetermined {
                permissionService.requestCameraAccess { [weak self] in
                    self?.presentPermissionsDialog()
                }
            } else {
                permissionService.openCameraSettings()
                representWhenActive()
            }
        case NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + 3):
            if !inputMonitoringGranted && InputMonitoringPermission.request() {
                presentPermissionsDialog()
            } else {
                InputMonitoringPermission.openSettings()
                representWhenActive()
            }
        default:
            break
        }
    }

    /// Requests dictation's microphone and Speech Recognition permissions in
    /// sequence so two macOS privacy prompts never compete for the foreground.
    private func requestSnipDictationPermissions() {
        let requestSpeech: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self, self.permissionService.speechRecognitionStatus() == .notDetermined else { return }
            self.permissionService.requestSpeechRecognitionAccess(completion: nil)
        }
        if permissionService.microphoneStatus() == .notDetermined {
            permissionService.requestMicrophoneAccess {
                requestSpeech()
            }
        } else {
            requestSpeech()
        }
    }

    /// Re-presents the permissions dialog the next time TeachLens becomes active.
    /// Used after sending the user to System Settings so the dialog reappears
    /// when they switch back, without stealing focus from System Settings.
    private func representWhenActive() {
        if let permissionReactivationObserver {
            NotificationCenter.default.removeObserver(permissionReactivationObserver)
            self.permissionReactivationObserver = nil
        }
        permissionReactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let observer = self.permissionReactivationObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self.permissionReactivationObserver = nil
                }
                self.presentPermissionsDialog()
            }
        }
    }

    @objc func quit() {
        hotkeyService.stop()
        NSApplication.shared.terminate(nil)
    }
}