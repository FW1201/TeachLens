import AppKit

/// "Start class" / "End class": one switch for the whole teaching setup.
///
/// Starting checks the two permissions a class depends on (Screen Recording
/// and Input Monitoring), remembers what is on now, applies the current course
/// mode (Lecture when none is chosen) and shows the Graphical Mode toolbar.
/// Ending puts everything back as it was before the class.
@MainActor
final class ClassSession: ObservableObject {
    @Published private(set) var inClass = false

    private let courseModes: CourseModeController
    private let testCenter: TestCenter
    private var before: CourseMode?
    private var beforeModeID: String?

    /// Called whenever `inClass` changes (menu title, menu-bar icon).
    var onChange: ((Bool) -> Void)?
    /// Opens Settings ▸ Check & Test.
    var openCheck: (() -> Void)?
    /// Whether a screen recording is running, for the reminder at the end.
    var isRecording: (() -> Bool)?

    /// Permissions without which a class visibly fails.
    static let requiredPermissions: Set<String> = ["screen", "input"]

    init(courseModes: CourseModeController, testCenter: TestCenter) {
        self.courseModes = courseModes
        self.testCenter = testCenter
    }

    @objc func toggle() {
        inClass ? end() : start()
    }

    /// The mode a class starts with: the current one, or Lecture.
    var startingMode: CourseMode {
        let id = courseModes.currentModeID
        return courseModes.allModes.first { $0.id == id && $0.id != "break" }
            ?? CourseMode.builtIns.first { $0.id == "lecture" }!
    }

    func start() {
        guard !inClass else { return }
        before = courseModes.snapshot(name: "before-class")
        beforeModeID = courseModes.currentModeID

        var mode = startingMode
        mode.startBreakTimer = false
        mode.showToolbar = true
        courseModes.apply(mode, showToast: false)
        inClass = true
        onChange?(true)

        testCenter.refreshPermissions()
        let missing = testCenter.permissions.filter {
            Self.requiredPermissions.contains($0.id) && $0.state != .granted
        }
        if missing.isEmpty {
            GlassToast.shared.show(symbol: "play.circle.fill", title: L10n.t("Class started", "開始上課"),
                                   message: mode.name, tint: .green)
        } else {
            let names = missing.map(\.title).joined(separator: L10n.t(", ", "、"))
            GlassToast.shared.show(
                symbol: "exclamationmark.triangle.fill",
                title: L10n.t("Class started — permission needed", "已開始上課，但缺少權限"),
                message: names, tint: .orange,
                action: GlassToast.Action(title: L10n.t("Fix", "修正")) { [weak self] in self?.openCheck?() }
            )
        }
    }

    func end() {
        guard inClass else { return }
        if let before {
            courseModes.apply(before, showToast: false)
        }
        courseModes.markCurrent(beforeModeID)
        before = nil
        inClass = false
        onChange?(false)

        if isRecording?() == true {
            GlassToast.shared.show(symbol: "record.circle", title: L10n.t("Class ended", "已下課"),
                                   message: L10n.t("Recording is still running — stop it to save the video.",
                                                   "錄影仍在進行，記得停止並存檔。"),
                                   tint: .red, duration: 4)
        } else {
            GlassToast.shared.show(symbol: "stop.circle.fill", title: L10n.t("Class ended", "已下課"),
                                   message: L10n.t("Your setup before class is back.", "已還原上課前的設定。"))
        }
    }
}
