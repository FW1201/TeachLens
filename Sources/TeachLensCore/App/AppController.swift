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
    /// Set by AppDelegate before Settings is first opened.
    var teaching: TeachingControllers?
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
        spotlightController: spotlightController,
        teaching: teaching
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

    func reloadSettingsForLanguageChange() {
        settingsWindowController.reloadForLanguageChange()
    }

    @objc func showSettings() {
        settingsWindowController.show()
    }

    /// See `SettingsWindowController.prepareWindow()`.
    func prepareSettingsWindow() {
        settingsWindowController.prepareWindow()
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
            case .granted: return L10n.t("Granted", "已允許")
            case .denied: return L10n.t("Denied", "已拒絕")
            case .notDetermined: return L10n.t("Not requested", "尚未要求")
            }
        }
        func describe(_ status: SpeechRecognitionPermission) -> String {
            switch status {
            case .granted: return L10n.t("Granted", "已允許")
            case .denied: return L10n.t("Denied", "已拒絕")
            case .notDetermined: return L10n.t("Not requested", "尚未要求")
            }
        }

        let alert = NSAlert()
        alert.messageText = L10n.t("TeachLens Permissions", "TeachLens 權限")
        let screenText = screenGranted ? L10n.t("Granted", "已允許") : L10n.t("Missing", "未允許")
        let inputText = inputMonitoringGranted ? L10n.t("Granted", "已允許") : L10n.t("Missing", "未允許")
        alert.informativeText = L10n.t("""
        Screen Recording: \(screenText)
        Input Monitoring: \(inputText)
        Microphone: \(describe(micStatus))
        Speech Recognition: \(describe(speechStatus))
        Camera: \(describe(camStatus))

        Screen Recording: zoom, snip, record. Input Monitoring: keystrokes. Microphone + Speech Recognition: captions. Camera: optional.
        Relaunch TeachLens after granting Screen Recording or Input Monitoring.
        """, """
        螢幕錄製：\(screenText)
        輸入監控：\(inputText)
        麥克風：\(describe(micStatus))
        語音辨識：\(describe(speechStatus))
        相機：\(describe(camStatus))

        螢幕錄製：放大、截圖、錄影。輸入監控：按鍵顯示。麥克風＋語音辨識：字幕。相機：選用。
        開啟螢幕錄製或輸入監控後，請重新打開 TeachLens。
        """)
        alert.addButton(withTitle: L10n.t("Done", "完成"))
        alert.addButton(withTitle: screenGranted ? L10n.t("Screen Recording Settings…", "螢幕錄製設定…") : L10n.t("Grant Screen Recording…", "允許螢幕錄製…"))
        alert.addButton(withTitle: micStatus == .notDetermined ? L10n.t("Grant Microphone…", "允許麥克風…") : L10n.t("Microphone Settings…", "麥克風設定…"))
        alert.addButton(withTitle: speechStatus == .notDetermined ? L10n.t("Grant Speech Recognition…", "允許語音辨識…") : L10n.t("Speech Recognition Settings…", "語音辨識設定…"))
        alert.addButton(withTitle: camStatus == .notDetermined ? L10n.t("Grant Camera…", "允許相機…") : L10n.t("Camera Settings…", "相機設定…"))
        alert.addButton(withTitle: inputMonitoringGranted ? L10n.t("Input Monitoring Settings…", "輸入監控設定…") : L10n.t("Grant Input Monitoring…", "允許輸入監控…"))
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