import AppKit
import AVFoundation
import Speech

/// The controllers the teaching settings panes and Check & Test need.
@MainActor
struct TeachingControllers {
    let keystrokes: KeystrokeController
    let spotlight: SpotlightController
    let captions: CaptionController
    let courseModes: CourseModeController
    let whiteboard: WhiteboardController
    let testCenter: TestCenter
    /// Runs an app command directly (the same path a shortcut takes).
    let run: (AppCommand) -> Void
}

/// One permission row in the pre-class check.
struct PermissionCheck: Identifiable, Equatable {
    enum State: Equatable { case granted, missing, notAsked }

    var id: String
    var title: String
    var purpose: String
    var state: State
    var needsRelaunch: Bool
}

/// Status the Check & Test pane shows: build identity, permissions and the
/// last global shortcut received.
@MainActor
final class TestCenter: ObservableObject {
    @Published private(set) var lastShortcut: String?
    @Published private(set) var lastShortcutAt: Date?
    @Published private(set) var permissions: [PermissionCheck] = []

    private let permissionService: PermissionService

    init(permissionService: PermissionService) {
        self.permissionService = permissionService
        refreshPermissions()
    }

    // MARK: Shortcut echo

    /// Called for every global shortcut before it runs, so testers can see
    /// whether the shortcut arrived at all.
    func record(_ command: AppCommand) {
        lastShortcut = Self.describe(command)
        lastShortcutAt = Date()
    }

    static func describe(_ command: AppCommand) -> String {
        switch command {
        case .activateStaticZoom: return L10n.t("Static Zoom", "靜態放大")
        case .activateLiveZoom: return L10n.t("Live Zoom", "即時放大")
        case .activateDrawWithoutZoom: return L10n.t("Draw", "畫筆")
        case .zoomIn: return L10n.t("Zoom In", "放大")
        case .zoomOutOrExit: return L10n.t("Zoom Out", "縮小")
        case .snipRegion(let save): return save ? L10n.t("Snip to File", "截圖存檔") : L10n.t("Snip", "截圖")
        case .snipOcr: return L10n.t("Text Recognition", "文字辨識")
        case .startPanorama: return L10n.t("Panorama", "長截圖")
        case .toggleRecording(let region): return region ? L10n.t("Record Region", "錄製區域") : L10n.t("Record Screen", "錄製全螢幕")
        case .toggleBreakTimer: return L10n.t("Break Timer", "休息計時器")
        case .toggleDemoMirror: return "DemoMirror"
        case .toggleKeystrokes: return L10n.t("Show Keystrokes", "顯示按鍵")
        case .toggleSpotlight: return L10n.t("Spotlight", "聚光燈")
        case .toggleCaptions: return L10n.t("Live Captions", "即時字幕")
        case .toggleWhiteboard: return L10n.t("Whiteboard", "白板")
        default: return String(describing: command)
        }
    }

    // MARK: Permissions

    func refreshPermissions() {
        func state(_ mic: MicrophonePermission) -> PermissionCheck.State {
            switch mic {
            case .granted: return .granted
            case .denied: return .missing
            case .notDetermined: return .notAsked
            }
        }
        let speech: PermissionCheck.State
        switch permissionService.speechRecognitionStatus() {
        case .granted: speech = .granted
        case .denied: speech = .missing
        case .notDetermined: speech = .notAsked
        }
        permissions = [
            PermissionCheck(id: "screen", title: L10n.t("Screen Recording", "螢幕錄製"),
                            purpose: L10n.t("Zoom, snip, record, whiteboard screenshots", "放大、截圖、錄影、白板插入截圖"),
                            state: permissionService.currentState().screenCapture.isGranted ? .granted : .missing,
                            needsRelaunch: true),
            PermissionCheck(id: "input", title: L10n.t("Input Monitoring", "輸入監控"),
                            purpose: L10n.t("Showing keystrokes and mouse clicks", "顯示按鍵與滑鼠點擊"),
                            state: InputMonitoringPermission.isGranted ? .granted : .missing,
                            needsRelaunch: true),
            PermissionCheck(id: "mic", title: L10n.t("Microphone", "麥克風"),
                            purpose: L10n.t("Live captions, recording audio", "即時字幕、錄影收音"),
                            state: state(permissionService.microphoneStatus()), needsRelaunch: false),
            PermissionCheck(id: "speech", title: L10n.t("Speech Recognition", "語音辨識"),
                            purpose: L10n.t("Live captions", "即時字幕"),
                            state: speech, needsRelaunch: false),
            PermissionCheck(id: "camera", title: L10n.t("Camera (optional)", "相機（選用）"),
                            purpose: L10n.t("Webcam picture-in-picture in recordings", "錄影時的相機子母畫面"),
                            state: state(permissionService.cameraStatus()), needsRelaunch: false),
        ]
    }

    func fix(_ check: PermissionCheck) {
        let refresh: @MainActor @Sendable () -> Void = { [weak self] in self?.refreshPermissions() }
        switch check.id {
        case "screen":
            if !permissionService.requestScreenCaptureAccess() { permissionService.openSystemSettings() }
        case "input":
            if !InputMonitoringPermission.request() { InputMonitoringPermission.openSettings() }
        case "mic":
            if check.state == .notAsked {
                permissionService.requestMicrophoneAccess(completion: refresh)
            } else {
                permissionService.openMicrophoneSettings()
            }
        case "speech":
            if check.state == .notAsked {
                permissionService.requestSpeechRecognitionAccess(completion: refresh)
            } else {
                permissionService.openSpeechRecognitionSettings()
            }
        case "camera":
            if check.state == .notAsked {
                permissionService.requestCameraAccess(completion: refresh)
            } else {
                permissionService.openCameraSettings()
            }
        default:
            break
        }
        refreshPermissions()
    }

    // MARK: Diagnostics

    func diagnostics(keystrokes: KeystrokeController, spotlight: SpotlightController, captions: CaptionController) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var lines = [
            "TeachLens \(AppInfo.version) (\(AppInfo.commit))",
            "Bundle: \(AppInfo.bundleIdentifier)\(AppInfo.isDevBuild ? " [dev build]" : "")",
            "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "Language: \(L10n.language.rawValue) (\(Locale.preferredLanguages.first ?? "?"))",
            "Liquid Glass available: \(KeystrokeGlassSupport.isLiquidGlassAvailable)",
            "",
            "Permissions:",
        ]
        for p in permissions { lines.append("  \(p.id): \(p.state)") }
        lines += [
            "",
            "Keystrokes: enabled=\(keystrokes.settings.enabled) listening=\(keystrokes.isActive) filter=\(keystrokes.settings.filter.rawValue) windows=\(keystrokes.settings.windowsEquivalent)",
            "Spotlight: on=\(spotlight.spotlightOn) highlight=\(spotlight.settings.highlightEnabled)",
            "Captions: running=\(captions.isRunning) language=\(captions.settings.localeIdentifier)",
            "Last shortcut: \(lastShortcut ?? "none")",
        ]
        return lines.joined(separator: "\n")
    }
}
