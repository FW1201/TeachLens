import AppKit
import SwiftUI

/// Owns the keystroke feature: the event tap, the Keyviz-style state machine,
/// the click-through overlay panel and the status-menu submenu.
@MainActor
final class KeystrokeController: NSObject, NSMenuItemValidation {
    private let store: KeystrokeSettingsStore
    private(set) var settings: KeystrokeSettings
    private var engine: KeystrokeEngine
    private let model: KeystrokeOverlayModel
    private var tap: KeystrokeTap?
    private var panel: NSPanel?
    private var timer: Timer?
    private var screenFrame: CGRect = .zero
    private var didShowPermissionHint = false
    private var permissionRetryTimer: Timer?

    /// Called after the toggle hotkey changes so global hotkeys can re-register.
    var onHotkeyChange: (() -> Void)?

    init(store: KeystrokeSettingsStore = KeystrokeSettingsStore()) {
        self.store = store
        let settings = store.load()
        self.settings = settings
        self.engine = KeystrokeEngine(config: settings.engineConfig)
        self.model = KeystrokeOverlayModel(settings: settings)
        super.init()
        self.tap = KeystrokeTap { [weak self] input in
            self?.handle(input)
        }
    }

    var isActive: Bool { tap?.isRunning ?? false }

    func start() {
        if settings.enabled {
            // At launch, rely on the system prompt only; a second modal alert
            // on top of it (and the first-launch Settings window) is noise.
            activate(promptForPermission: true, showHint: false)
        }
        // If Input Monitoring is granted while TeachLens is running, start
        // listening without requiring the menu toggle.
        let retry = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.settings.enabled, !self.isActive, InputMonitoringPermission.isGranted else { return }
                self.activate(promptForPermission: false, showHint: false)
            }
        }
        RunLoop.main.add(retry, forMode: .common)
        permissionRetryTimer = retry
    }

    func stop() {
        deactivate()
    }

    @objc func toggle() {
        update { $0.enabled.toggle() }
    }

    /// The overlay's observable state, for the Settings pane.
    var observableModel: KeystrokeOverlayModel { model }

    func update(_ change: (inout KeystrokeSettings) -> Void) {
        let old = settings
        change(&settings)
        guard settings != old else { return }
        store.save(settings)
        engine.config = settings.engineConfig
        model.settings = settings
        publish()
        if old.enabled != settings.enabled {
            if settings.enabled {
                didShowPermissionHint = false
                activate(promptForPermission: true)
            } else {
                deactivate()
            }
        }
        if old.toggleKeyCode != settings.toggleKeyCode || old.toggleModifiers != settings.toggleModifiers {
            onHotkeyChange?()
        }
    }

    // MARK: Activation

    private func activate(promptForPermission: Bool, showHint: Bool = true) {
        if !InputMonitoringPermission.isGranted && promptForPermission {
            InputMonitoringPermission.request()
        }
        guard let tap, tap.start() else {
            if showHint { showPermissionHintOnce() }
            return
        }
        ensurePanel()
        startTimer()
    }

    private func deactivate() {
        tap?.stop()
        timer?.invalidate()
        timer = nil
        engine.reset()
        model.groups = []
        model.ripples = []
        panel?.orderOut(nil)
    }

    private func showPermissionHintOnce() {
        guard !didShowPermissionHint else { return }
        didShowPermissionHint = true
        let alert = NSAlert()
        alert.messageText = L10n.t("Allow Input Monitoring to show keystrokes", "顯示按鍵需要「輸入監控」權限")
        alert.informativeText = L10n.t(
            "TeachLens only listens to which keys you press; it never changes or records your input. Turn on TeachLens in System Settings ▸ Privacy & Security ▸ Input Monitoring, then quit and reopen TeachLens.",
            "TeachLens 只會讀取你按了哪些鍵，不會修改或記錄輸入內容。請到「系統設定 ▸ 隱私權與安全性 ▸ 輸入監控」開啟 TeachLens，再結束並重新打開。"
        )
        alert.addButton(withTitle: L10n.t("Open Input Monitoring Settings…", "打開輸入監控設定…"))
        alert.addButton(withTitle: L10n.t("Not Now", "稍後"))
        if let icon = TeachLensAppIcon.standardIcon() {
            alert.icon = icon
        }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            InputMonitoringPermission.openSettings()
        }
    }

    // MARK: Test center

    /// The demo sequence used by Settings ▸ Check & Test: ⌘C, ⇧⌘4, ⌘Z ×3.
    /// Times are seconds from the start.
    static let demoSequence: [(TimeInterval, KeystrokeInput.Kind)] = [
        (0.0, .keyDown(name: KeyName.metaLeft)), (0.15, .keyDown(name: "KeyC")),
        (0.30, .keyUp(name: "KeyC")), (0.45, .keyUp(name: KeyName.metaLeft)),
        (1.4, .keyDown(name: KeyName.shiftLeft)), (1.5, .keyDown(name: KeyName.metaLeft)),
        (1.65, .keyDown(name: "Num4")), (1.8, .keyUp(name: "Num4")),
        (1.9, .keyUp(name: KeyName.metaLeft)), (1.95, .keyUp(name: KeyName.shiftLeft)),
        (3.0, .keyDown(name: KeyName.metaLeft)),
        (3.15, .keyDown(name: "KeyZ")), (3.25, .keyUp(name: "KeyZ")),
        (3.45, .keyDown(name: "KeyZ")), (3.55, .keyUp(name: "KeyZ")),
        (3.75, .keyDown(name: "KeyZ")), (3.85, .keyUp(name: "KeyZ")),
        (4.0, .keyUp(name: KeyName.metaLeft)),
    ]

    /// Plays the demo through the real HUD. Needs no Input Monitoring, so the
    /// HUD can be checked and screenshotted on any Mac.
    func playDemo() {
        ensurePanel()
        startTimer()
        let mouse = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let x = Double(mouse.x), y = Double(primaryHeight - mouse.y)
        for (delay, kind) in Self.demoSequence {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                self?.handle(KeystrokeInput(kind: kind, x: x, y: y))
            }
        }
    }

    /// The display groups the demo produces, for self-tests.
    /// The combination on screen at the end of each step of the demo (a
    /// pause of more than half a second ends a step), for self-tests.
    static func demoGroups() -> [KeystrokeDisplayGroup] {
        var engine = KeystrokeEngine(config: KeystrokeEngineConfig())
        var shown: [KeystrokeDisplayGroup] = []
        for (index, step) in demoSequence.enumerated() {
            switch step.1 {
            case .keyDown(let name): engine.keyDown(name, at: step.0)
            case .keyUp(let name): engine.keyUp(name, at: step.0)
            default: break
            }
            let next = index + 1 < demoSequence.count ? demoSequence[index + 1].0 : .infinity
            if next - step.0 > 0.5, let group = engine.groups.last {
                shown.append(KeystrokeDisplayGroup.make(from: group, index: shown.count))
            }
        }
        return shown
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        engine.tick(at: Self.now())
        // Nothing held or shown: skip the work entirely (the common idle case).
        if engine.groups.isEmpty && model.groups.isEmpty { return }
        // Visibility also changes without the groups changing (a held modifier
        // crossing its show delay), so always re-check; publish() skips no-ops.
        publish()
    }

    private static func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    // MARK: Input

    private func handle(_ input: KeystrokeInput) {
        let now = Self.now()
        switch input.kind {
        case .keyDown(let name):
            followPointer(x: input.x, y: input.y)
            engine.keyDown(name, at: now)
        case .keyUp(let name):
            engine.keyUp(name, at: now)
        case .mouseDown(let button):
            followPointer(x: input.x, y: input.y)
            engine.mouseDown(button, x: input.x, y: input.y, at: now)
            if settings.showClickRipples {
                addRipple(x: input.x, y: input.y, secondary: button != KeyName.mouseLeft)
            }
        case .mouseUp(let button):
            engine.mouseUp(button, at: now)
        case .mouseDragged:
            engine.mouseMoved(x: input.x, y: input.y, at: now)
        case .scroll(let deltaY):
            engine.scroll(deltaY: deltaY, at: now)
        }
        publish()
    }

    private func publish() {
        let all = engine.groups
        let groups = engine.visibleGroups(at: Self.now()).map { group in
            KeystrokeDisplayGroup.make(from: group, index: all.firstIndex(of: group) ?? 0)
        }
        if groups != model.groups {
            model.groups = groups
        }
    }

    private func addRipple(x: Double, y: Double, secondary: Bool) {
        guard panel != nil else { return }
        let local = CGPoint(x: x - screenFrame.minX, y: y - screenFrame.minY)
        let ripple = ClickRipple(point: local, isSecondary: secondary)
        model.ripples.append(ripple)
        let id = ripple.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            self?.model.ripples.removeAll { $0.id == id }
        }
    }

    // MARK: Panel

    /// The screen frame in CoreGraphics global coordinates (top-left origin).
    private static func cgFrame(of screen: NSScreen) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let f = screen.frame
        return CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
    }

    private func followPointer(x: Double, y: Double) {
        let point = CGPoint(x: x, y: y)
        if screenFrame.contains(point), panel != nil { return }
        guard let screen = NSScreen.screens.first(where: { Self.cgFrame(of: $0).contains(point) })
                ?? NSScreen.main else { return }
        moveToScreen(screen)
    }

    private func ensurePanel() {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.animationBehavior = .none
            let hosting = NSHostingView(rootView: KeystrokeHUDView(model: model))
            hosting.autoresizingMask = [.width, .height]
            panel.contentView = hosting
            self.panel = panel
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        if let screen {
            moveToScreen(screen)
        }
        panel?.orderFrontRegardless()
    }

    private func moveToScreen(_ screen: NSScreen) {
        screenFrame = Self.cgFrame(of: screen)
        panel?.setFrame(screen.frame, display: true)
        panel?.orderFrontRegardless()
    }

    // MARK: Capture coordination

    /// The HUD window, to keep it out of zoom source captures.
    var windowNumberForCaptureExclusion: Int? {
        guard let panel, panel.isVisible else { return nil }
        return panel.windowNumber
    }

    private var cachedRecordingFrame: KeystrokeRecordingFrame?
    private var cachedRecordingKey: (groups: [KeystrokeDisplayGroup], settings: KeystrokeSettings, screen: CGRect)?

    /// Renders the current combinations for recordings made while a zoom or
    /// draw overlay is up. Rendered with the opaque style (glass cannot be
    /// rasterized off-screen) and cached until the combinations change.
    func recordingFrame() -> KeystrokeRecordingFrame? {
        guard isActive, let panel, !model.groups.isEmpty else { return nil }
        let screen = panel.frame
        if let key = cachedRecordingKey, key.groups == model.groups, key.settings == settings, key.screen == screen {
            return cachedRecordingFrame
        }
        let s = CGFloat(min(max(settings.scale, 0.5), 3))
        let view = KeystrokeStackView(groups: model.groups, position: settings.position, scale: s, glass: .solid,
                                      showWindows: settings.windowsEquivalent, primary: settings.primaryPlatform)
            .padding(16 * s)
        let renderer = ImageRenderer(content: view)
        renderer.scale = panel.backingScaleFactor
        guard let image = renderer.cgImage else { return nil }
        let size = CGSize(
            width: CGFloat(image.width) / renderer.scale,
            height: CGFloat(image.height) / renderer.scale
        )
        let margin = CGFloat(settings.margin) - 16 * s
        let x: CGFloat
        switch settings.position {
        case .bottomLeft, .topLeft: x = screen.minX + margin
        case .bottomCenter, .topCenter: x = screen.midX - size.width / 2
        case .bottomRight, .topRight: x = screen.maxX - margin - size.width
        }
        let y = settings.position.isTop ? screen.maxY - margin - size.height : screen.minY + margin
        let frame = KeystrokeRecordingFrame(image: image, frame: CGRect(origin: CGPoint(x: x, y: y), size: size))
        cachedRecordingFrame = frame
        cachedRecordingKey = (model.groups, settings, screen)
        return frame
    }

    // MARK: Menu

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Keystrokes")
        func add(_ title: String, _ action: Selector, _ represented: String? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = represented
            menu.addItem(item)
        }
        add(L10n.t("Shortcuts Only", "只顯示快捷鍵"), #selector(toggleShortcutsOnly))
        add(L10n.t("Show Mouse Clicks", "顯示滑鼠點擊"), #selector(toggleMouseEvents))
        add(L10n.t("Click Ripples", "點擊漣漪"), #selector(toggleClickRipples))
        add(L10n.t("Keep History", "保留歷史"), #selector(toggleHistory))
        add(L10n.t("Windows Equivalents", "Windows 對照"), #selector(toggleWindowsEquivalent))
        menu.addItem(.separator())
        for platform in KeystrokePlatform.allCases {
            add(platform.title, #selector(setPrimaryPlatform(_:)), platform.rawValue)
        }
        menu.addItem(.separator())
        for position in KeystrokePosition.allCases {
            add(position.title, #selector(setPosition(_:)), position.rawValue)
        }
        menu.addItem(.separator())
        for glass in KeystrokeGlass.allCases {
            add(glass.title, #selector(setGlass(_:)), glass.rawValue)
        }
        menu.addItem(.separator())
        add(L10n.t("Larger", "放大"), #selector(increaseScale))
        add(L10n.t("Smaller", "縮小"), #selector(decreaseScale))
        return menu
    }

    @objc private func toggleShortcutsOnly() {
        if settings.filter != .none && !Self.confirmEveryKey() { return }
        update { $0.filter = $0.filter == .none ? .modifiers : .none }
    }

    /// Asks before showing every key: typed text becomes visible to everyone
    /// watching the screen.
    static func confirmEveryKey() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.t("Show every key you type?", "要顯示你打的每個字嗎？")
        alert.informativeText = L10n.t(
            "Everything you type, not just shortcuts, will appear on screen and in recordings. Turn it off before typing anything private while sharing your screen.",
            "不只快捷鍵，你打的每個字都會出現在畫面和錄影上。分享螢幕時要輸入私人內容前，請先切回「只顯示快捷鍵」。"
        )
        alert.addButton(withTitle: L10n.t("Show Every Key", "顯示每個鍵"))
        alert.addButton(withTitle: L10n.t("Cancel", "取消"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc private func toggleMouseEvents() {
        update { $0.showMouseEvents.toggle() }
    }

    @objc private func toggleClickRipples() {
        update { $0.showClickRipples.toggle() }
    }

    @objc func toggleWindowsEquivalent() {
        update { $0.windowsEquivalent.toggle() }
    }

    @objc private func setPrimaryPlatform(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let platform = KeystrokePlatform(rawValue: raw) else { return }
        update { $0.primaryPlatform = platform }
    }

    @objc private func toggleHistory() {
        update { $0.showHistory.toggle() }
        engine.clearGroups()
        publish()
    }

    @objc private func setPosition(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let position = KeystrokePosition(rawValue: raw) else { return }
        update { $0.position = position }
    }

    @objc private func setGlass(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let glass = KeystrokeGlass(rawValue: raw) else { return }
        update { $0.glass = glass }
    }

    @objc private func increaseScale() {
        update { $0.scale = min(3, ($0.scale + 0.25)) }
    }

    @objc private func decreaseScale() {
        update { $0.scale = max(0.5, ($0.scale - 0.25)) }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let raw = menuItem.representedObject as? String
        switch menuItem.action {
        case #selector(toggle):
            menuItem.state = settings.enabled ? .on : .off
        case #selector(toggleShortcutsOnly):
            menuItem.state = settings.filter == .none ? .off : .on
        case #selector(toggleMouseEvents):
            menuItem.state = settings.showMouseEvents ? .on : .off
        case #selector(toggleClickRipples):
            menuItem.state = settings.showClickRipples ? .on : .off
        case #selector(toggleHistory):
            menuItem.state = settings.showHistory ? .on : .off
        case #selector(toggleWindowsEquivalent):
            menuItem.state = settings.windowsEquivalent ? .on : .off
        case #selector(setPrimaryPlatform(_:)):
            menuItem.state = (menuItem.representedObject as? String) == settings.primaryPlatform.rawValue ? .on : .off
        case #selector(setPosition(_:)):
            menuItem.state = raw == settings.position.rawValue ? .on : .off
        case #selector(setGlass(_:)):
            menuItem.state = raw == settings.glass.rawValue ? .on : .off
        case #selector(increaseScale):
            return settings.scale < 3
        case #selector(decreaseScale):
            return settings.scale > 0.5
        default:
            break
        }
        return true
    }
}
