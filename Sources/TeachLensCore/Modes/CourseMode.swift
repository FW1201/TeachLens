import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A named combination of TeachLens features for one teaching situation.
struct CourseMode: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var symbol: String = "rectangle.on.rectangle"
    var keystrokes = true
    var keystrokeFilter: KeystrokeFilter = .modifiers
    var keystrokeHistory = false
    var keystrokeScale: Double = 1
    var spotlight = false
    var cursorHighlight = false
    var captions = false
    var startBreakTimer = false

    static let builtInIDs: Set<String> = ["lecture", "coding", "focus", "break"]

    var isBuiltIn: Bool { Self.builtInIDs.contains(id) }

    static var builtIns: [CourseMode] {
        [
            CourseMode(id: "lecture", name: L10n.t("Lecture", "講解"), symbol: "person.wave.2",
                       keystrokes: true, keystrokeFilter: .modifiers, cursorHighlight: true, captions: true),
            CourseMode(id: "coding", name: L10n.t("Coding Demo", "程式示範"), symbol: "chevron.left.forwardslash.chevron.right",
                       keystrokes: true, keystrokeFilter: .none, keystrokeHistory: true, keystrokeScale: 1.25,
                       cursorHighlight: true),
            CourseMode(id: "focus", name: L10n.t("Focus", "重點強調"), symbol: "light.max",
                       keystrokes: false, spotlight: true),
            CourseMode(id: "break", name: L10n.t("Break", "休息"), symbol: "cup.and.saucer",
                       keystrokes: false, startBreakTimer: true),
        ]
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, symbol, keystrokes, keystrokeFilter, keystrokeHistory, keystrokeScale
        case spotlight, cursorHighlight, captions, startBreakTimer
    }

    init(id: String, name: String, symbol: String = "rectangle.on.rectangle", keystrokes: Bool = true,
         keystrokeFilter: KeystrokeFilter = .modifiers, keystrokeHistory: Bool = false, keystrokeScale: Double = 1,
         spotlight: Bool = false, cursorHighlight: Bool = false, captions: Bool = false, startBreakTimer: Bool = false) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.keystrokes = keystrokes
        self.keystrokeFilter = keystrokeFilter
        self.keystrokeHistory = keystrokeHistory
        self.keystrokeScale = keystrokeScale
        self.spotlight = spotlight
        self.cursorHighlight = cursorHighlight
        self.captions = captions
        self.startBreakTimer = startBreakTimer
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "rectangle.on.rectangle"
        keystrokes = try c.decodeIfPresent(Bool.self, forKey: .keystrokes) ?? true
        keystrokeFilter = (try? c.decodeIfPresent(KeystrokeFilter.self, forKey: .keystrokeFilter)) ?? .modifiers
        keystrokeHistory = try c.decodeIfPresent(Bool.self, forKey: .keystrokeHistory) ?? false
        keystrokeScale = try c.decodeIfPresent(Double.self, forKey: .keystrokeScale) ?? 1
        spotlight = try c.decodeIfPresent(Bool.self, forKey: .spotlight) ?? false
        cursorHighlight = try c.decodeIfPresent(Bool.self, forKey: .cursorHighlight) ?? false
        captions = try c.decodeIfPresent(Bool.self, forKey: .captions) ?? false
        startBreakTimer = try c.decodeIfPresent(Bool.self, forKey: .startBreakTimer) ?? false
    }
}

/// The file format for importing and exporting custom modes.
struct CourseModeFile: Codable, Equatable {
    var format = "teachlens.course-modes"
    var version = 1
    var modes: [CourseMode]
}

struct CourseModeStore {
    static let customKey = "courseModes.custom"
    static let currentKey = "courseModes.current"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func customModes() -> [CourseMode] {
        guard let data = defaults.data(forKey: Self.customKey),
              let modes = try? JSONDecoder().decode([CourseMode].self, from: data) else { return [] }
        return modes.filter { !$0.isBuiltIn }
    }

    func saveCustomModes(_ modes: [CourseMode]) {
        if let data = try? JSONEncoder().encode(modes.filter { !$0.isBuiltIn }) {
            defaults.set(data, forKey: Self.customKey)
        }
    }

    var currentModeID: String? {
        get { defaults.string(forKey: Self.currentKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.currentKey) }
    }

    static func encode(_ modes: [CourseMode]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(CourseModeFile(modes: modes))
    }

    /// Accepts the export format or a bare array; built-in ids get a new id so
    /// an import never replaces a built-in mode.
    static func decode(_ data: Data) throws -> [CourseMode] {
        let decoder = JSONDecoder()
        let modes: [CourseMode]
        if let file = try? decoder.decode(CourseModeFile.self, from: data) {
            modes = file.modes
        } else {
            modes = try decoder.decode([CourseMode].self, from: data)
        }
        return modes.map { mode in
            var copy = mode
            if copy.isBuiltIn || copy.id.isEmpty { copy.id = "custom-" + UUID().uuidString }
            return copy
        }
    }
}

/// Applies course modes to the feature controllers and shows a short toast.
@MainActor
final class CourseModeController: NSObject, NSMenuItemValidation {
    private let store: CourseModeStore
    private let keystrokes: KeystrokeController
    private let spotlight: SpotlightController
    private(set) var customModes: [CourseMode]
    private(set) var currentModeID: String?
    private var toastPanel: NSPanel?
    private var toastTask: Task<Void, Never>?

    /// Hooks for features owned elsewhere.
    var setCaptions: ((Bool) -> Void)?
    var captionsEnabled: (() -> Bool)?
    var startBreakTimer: (() -> Void)?

    init(keystrokes: KeystrokeController, spotlight: SpotlightController, store: CourseModeStore = CourseModeStore()) {
        self.store = store
        self.keystrokes = keystrokes
        self.spotlight = spotlight
        self.customModes = store.customModes()
        self.currentModeID = store.currentModeID
        super.init()
    }

    var allModes: [CourseMode] { CourseMode.builtIns + customModes }

    /// Re-applies the last chosen mode at launch (without starting a break).
    func restoreLastMode() {
        guard let id = currentModeID, let mode = allModes.first(where: { $0.id == id }) else { return }
        var restored = mode
        restored.startBreakTimer = false
        // Never switch the microphone on by itself at launch.
        restored.captions = false
        apply(restored, showToast: false)
    }

    func apply(_ mode: CourseMode, showToast: Bool = true) {
        keystrokes.update {
            $0.enabled = mode.keystrokes
            $0.filter = mode.keystrokeFilter
            $0.showHistory = mode.keystrokeHistory
            $0.scale = mode.keystrokeScale
        }
        spotlight.setSpotlight(mode.spotlight)
        spotlight.update { $0.highlightEnabled = mode.cursorHighlight }
        setCaptions?(mode.captions)
        if mode.startBreakTimer {
            startBreakTimer?()
        }
        currentModeID = mode.id
        store.currentModeID = mode.id
        if showToast {
            self.showToast(mode)
        }
    }

    /// A mode describing what is switched on right now.
    func snapshot(name: String) -> CourseMode {
        let k = keystrokes.settings
        return CourseMode(
            id: "custom-" + UUID().uuidString,
            name: name,
            symbol: "star",
            keystrokes: k.enabled,
            keystrokeFilter: k.filter,
            keystrokeHistory: k.showHistory,
            keystrokeScale: k.scale,
            spotlight: spotlight.spotlightOn,
            cursorHighlight: spotlight.settings.highlightEnabled,
            captions: captionsEnabled?() ?? false,
            startBreakTimer: false
        )
    }

    func addCustom(_ mode: CourseMode) {
        customModes.append(mode)
        store.saveCustomModes(customModes)
    }

    // MARK: Menu

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: L10n.t("Course Mode", "課程模式"))
        menu.autoenablesItems = true
        for mode in allModes {
            let item = NSMenuItem(title: mode.name, action: #selector(applyFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.id
            item.image = NSImage(systemSymbolName: mode.symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for (title, action) in [
            (L10n.t("Save Current Setup as Mode…", "將目前設定存成模式…"), #selector(saveCurrent)),
            (L10n.t("Import Modes…", "匯入模式…"), #selector(importModes)),
            (L10n.t("Export Modes…", "匯出模式…"), #selector(exportModes)),
            (L10n.t("Remove Custom Modes", "移除自訂模式"), #selector(removeCustomModes)),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    /// Rebuilds the submenu in place after modes change.
    weak var menuItem: NSMenuItem?

    private func rebuildMenu() {
        menuItem?.submenu = makeMenu()
    }

    @objc private func applyFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let mode = allModes.first(where: { $0.id == id }) else { return }
        apply(mode)
    }

    @objc private func saveCurrent() {
        let alert = NSAlert()
        alert.messageText = L10n.t("Save current setup as a course mode", "將目前設定存成課程模式")
        alert.informativeText = L10n.t(
            "Keystrokes, spotlight, cursor highlight and captions are saved as they are now.",
            "會記錄目前的按鍵顯示、聚光燈、游標強調和字幕狀態。"
        )
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = L10n.t("Mode name", "模式名稱")
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.t("Save", "儲存"))
        alert.addButton(withTitle: L10n.t("Cancel", "取消"))
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let mode = snapshot(name: name)
        addCustom(mode)
        currentModeID = mode.id
        store.currentModeID = mode.id
        rebuildMenu()
    }

    @objc private func importModes() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let modes = try CourseModeStore.decode(Data(contentsOf: url))
            customModes.append(contentsOf: modes)
            store.saveCustomModes(customModes)
            rebuildMenu()
        } catch {
            let alert = NSAlert()
            alert.messageText = L10n.t("Couldn’t import course modes", "無法匯入課程模式")
            alert.informativeText = L10n.t(
                "The file isn’t a TeachLens course-mode file. Export modes from TeachLens to see the expected format.",
                "這個檔案不是 TeachLens 課程模式檔。可先從 TeachLens 匯出一次，參考正確格式。"
            )
            alert.runModal()
        }
    }

    @objc private func exportModes() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "TeachLens Course Modes.json"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? CourseModeStore.encode(allModes).write(to: url)
    }

    @objc private func removeCustomModes() {
        customModes = []
        store.saveCustomModes([])
        if let id = currentModeID, !CourseMode.builtInIDs.contains(id) {
            currentModeID = nil
            store.currentModeID = nil
        }
        rebuildMenu()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(applyFromMenu(_:)) {
            menuItem.state = (menuItem.representedObject as? String) == currentModeID ? .on : .off
        } else if menuItem.action == #selector(removeCustomModes) {
            return !customModes.isEmpty
        }
        return true
    }

    // MARK: Toast

    private func showToast(_ mode: CourseMode) {
        let view = CourseModeToast(name: mode.name, symbol: mode.symbol)
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let panel = toastPanel ?? {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isReleasedWhenClosed = false
            return panel
        }()
        toastPanel = panel
        panel.contentView = hosting
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrame(NSRect(x: visible.maxX - size.width - 24, y: visible.maxY - size.height - 24,
                                  width: size.width, height: size.height), display: true)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled, let panel = self?.toastPanel else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                panel.animator().alphaValue = 0
            }
        }
    }
}

struct CourseModeToast: View {
    let name: String
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.t("Course mode", "課程模式"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text(name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .modifier(KeystrokePillBackground(glass: .automatic, scale: 1))
        .padding(16)
    }
}
