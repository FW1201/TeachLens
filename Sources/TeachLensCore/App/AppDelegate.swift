import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var graphicalTools: GraphicalTools?
    private var statusItem: NSStatusItem?
    private var appController: AppController?
    private var courseModeController: CourseModeController?
    private var whiteboardController: WhiteboardController?
    private var languageObserver: NSObjectProtocol?

    /// Rebuilds the status menu and Settings in the newly chosen language.
    private func applyLanguageChange() {
        guard let appController, let courseModeController else { return }
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = makeStatusItem(controller: appController, courseModes: courseModeController)
        appController.reloadSettingsForLanguageChange()
        graphicalTools?.languageChanged()
    }

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        guard SingleInstance.claim() else {
            NSApplication.shared.terminate(nil)
            return
        }

        TeachLensAppIcon.apply()

        let settingsStore = UserDefaultsSettingsStore()
        let savedSettings = settingsStore.load()
        if settingsStore.hasLaunchAtLoginPreference {
            LaunchAtLogin.applySavedPreference(savedSettings.launchAtLogin)
        } else if LaunchAtLogin.isEnabledOrPending {
            var migratedSettings = savedSettings
            migratedSettings.launchAtLogin = true
            settingsStore.save(migratedSettings)
        }
        let permissionService = SystemPermissionService()
        let userSelectedResourceAccess = UserDefaultsUserSelectedResourceAccess()
        let displayManager = SystemDisplayManager()
        let captureService = ScreenCaptureKitCaptureService(displayManager: displayManager)
        let overlayController = OverlayWindowController(
            userSelectedResourceAccess: userSelectedResourceAccess,
            settingsStore: settingsStore,
            permissionService: permissionService
        )
        let annotationController = AnnotationController()
        let viewportController = ZoomViewportController()

        let modeCoordinator = ModeCoordinator(
            settingsStore: settingsStore,
            permissionService: permissionService,
            displayManager: displayManager,
            captureService: captureService,
            overlayController: overlayController,
            annotationController: annotationController,
            viewportController: viewportController,
            userSelectedResourceAccess: userSelectedResourceAccess
        )

        let testCenter = TestCenter(permissionService: permissionService)
        let hotkeyService = HotkeyService(settingsStore: settingsStore) { command in
            Task { @MainActor in
                testCenter.record(command)
                modeCoordinator.handle(command)
            }
        }

        // Register Control+Up/Down zoom hotkeys only while live zoom is active.
        modeCoordinator.onBeginLiveZoomNavigation = { [weak hotkeyService] in
            hotkeyService?.beginLiveZoomNavigation()
        }
        modeCoordinator.onEndLiveZoomNavigation = { [weak hotkeyService] in
            hotkeyService?.endLiveZoomNavigation()
        }

        let keystrokeController = KeystrokeController()
        keystrokeController.onHotkeyChange = { [weak hotkeyService] in
            hotkeyService?.reloadHotkey()
        }
        modeCoordinator.onToggleKeystrokes = { [weak keystrokeController] in
            keystrokeController?.toggle()
        }
        let spotlightController = SpotlightController()
        spotlightController.onHotkeyChange = { [weak hotkeyService] in
            hotkeyService?.reloadHotkey()
        }
        modeCoordinator.onToggleSpotlight = { [weak spotlightController] in
            spotlightController?.toggleSpotlight()
        }
        let whiteboardController = WhiteboardController()
        self.whiteboardController = whiteboardController
        modeCoordinator.onToggleWhiteboard = { [weak whiteboardController] in
            whiteboardController?.toggle()
        }

        let captionController = CaptionController()
        captionController.onHotkeyChange = { [weak hotkeyService] in
            hotkeyService?.reloadHotkey()
        }
        modeCoordinator.onToggleCaptions = { [weak captionController] in
            captionController?.toggle()
        }
        modeCoordinator.additionalCaptureExclusions = { [weak self, weak keystrokeController, weak spotlightController, weak captionController] in
            [
                keystrokeController?.windowNumberForCaptureExclusion,
                spotlightController?.windowNumberForCaptureExclusion,
                captionController?.windowNumberForCaptureExclusion,
                self?.graphicalTools?.windowNumber
            ].compactMap { $0 }
        }
        modeCoordinator.keystrokeFrameProvider = { [weak keystrokeController] in
            keystrokeController?.recordingFrame()
        }

        let courseModeController = CourseModeController(keystrokes: keystrokeController, spotlight: spotlightController)
        courseModeController.setCaptions = { [weak captionController] on in
            captionController?.setEnabled(on)
        }
        courseModeController.captionsEnabled = { [weak captionController] in
            captionController?.isRunning ?? false
        }
        courseModeController.startBreakTimer = { [weak modeCoordinator] in
            guard let modeCoordinator, modeCoordinator.mode != .breakTimer else { return }
            modeCoordinator.handle(.toggleBreakTimer)
        }
        self.courseModeController = courseModeController

        appController = AppController(
            settingsStore: settingsStore,
            permissionService: permissionService,
            hotkeyService: hotkeyService,
            modeCoordinator: modeCoordinator,
            userSelectedResourceAccess: userSelectedResourceAccess,
            keystrokeController: keystrokeController,
            spotlightController: spotlightController,
            captionController: captionController
        )

        appController?.teaching = TeachingControllers(
            keystrokes: keystrokeController,
            spotlight: spotlightController,
            captions: captionController,
            courseModes: courseModeController,
            whiteboard: whiteboardController,
            testCenter: testCenter,
            run: { [weak modeCoordinator] command in modeCoordinator?.handle(command) }
        )

        if let teaching = appController?.teaching {
            graphicalTools = GraphicalTools(teaching: teaching)
            graphicalTools?.setVisible(UserDefaults.standard.bool(forKey: GraphicalTools.preference))
        }
        statusItem = makeStatusItem(controller: appController!, courseModes: courseModeController)
        languageObserver = NotificationCenter.default.addObserver(
            forName: L10n.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyLanguageChange() }
        }
        modeCoordinator.onToolsCaptureActivityChanged = { [weak self] active in
            self?.graphicalTools?.setCaptureActive(active)
        }
        modeCoordinator.onRecordingStateChanged = { [weak self, weak captionController] recording in
            self?.graphicalTools?.recording = recording
            self?.updateRecordingIndicator(recording)
            captionController?.recordingStateChanged(recording)
        }
        hotkeyService.start()
        keystrokeController.start()
        spotlightController.start()
        courseModeController.restoreLastMode()

        // On a fresh install, open Settings so the user has a clear entry point
        // instead of a silent menu-bar-only launch (issue #21). Upgrading users
        // are detected as returning by hasCompletedFirstLaunch, so they don't get
        // an unexpected pop-up. Persist the flag either way so later launches no
        // longer depend on the legacy migration sentinel.
        if !settingsStore.hasCompletedFirstLaunch {
            appController?.showSettings()
        }
        settingsStore.markFirstLaunchCompleted()

        // Build the Settings window once the launch work has settled, so the
        // first "Settings…" doesn't pause while 17 panes are laid out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            MainActor.assumeIsolated { self?.appController?.prepareSettingsWindow() }
        }
    }

    public func applicationDidChangeScreenParameters(_ notification: Notification) {
        graphicalTools?.screenConfigurationChanged()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        SingleInstance.release()
    }

    /// Swaps the menu-bar icon for a red record indicator while recording.
    private func updateRecordingIndicator(_ recording: Bool) {
        guard let button = statusItem?.button else { return }
        if recording {
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            let image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")?
                .withSymbolConfiguration(config)
            image?.size = NSSize(width: Self.menuBarIconGlyph, height: Self.menuBarIconGlyph)
            button.image = image
        } else {
            button.image = Self.menuBarIcon()
        }
    }

    private func makeStatusItem(controller: AppController, courseModes: CourseModeController) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Intentionally no autosaveName: persisting an absolute menu-bar slot makes
        // AppKit re-assert that position on every relaunch/relayout, which fights
        // menu-bar managers like Bartender and Ice (the icon snaps back out of their
        // "shown" section). Letting the system place the item keeps TeachLens compatible
        // with those tools; users can still Command-drag it to reorder.
        // Use the Windows ZoomIt icon (document with a magnifying glass) rendered
        // as a black template image so it tints to match the menu bar, following
        // the macOS convention for menu-bar icons.
        if let button = item.button {
            if let image = Self.menuBarIcon() {
                button.image = image
            } else {
                button.title = "TeachLens"
            }
        }

        let menu = NSMenu()
        for entry in Self.statusMenuEntries() {
            if entry.isSeparator {
                menu.addItem(.separator())
            } else {
                let menuItem = NSMenuItem(title: entry.title, action: entry.action, keyEquivalent: entry.keyEquivalent)
                menuItem.image = Self.menuSymbol(entry.symbol)
                menu.addItem(menuItem)
            }
        }

        for item in menu.items {
            item.target = controller
        }

        // Keystroke overlay: the toggle shows a checkmark via the keystroke
        // controller's menu validation, followed by its options submenu.
        if let index = menu.items.firstIndex(where: { $0.action == #selector(AppController.toggleKeystrokes) }) {
            let toggleItem = menu.items[index]
            toggleItem.target = controller.keystrokeController
            toggleItem.action = #selector(KeystrokeController.toggle)
            let optionsItem = NSMenuItem(title: L10n.t("Keystroke Options", "按鍵顯示選項"), action: nil, keyEquivalent: "")
            optionsItem.submenu = controller.keystrokeController.makeMenu()
            menu.insertItem(optionsItem, at: index + 1)
        }
        // Course modes sit right below Settings.
        let modesItem = NSMenuItem(title: L10n.t("Course Mode", "課程模式"), action: nil, keyEquivalent: "")
        modesItem.image = Self.menuSymbol("square.stack")
        modesItem.submenu = courseModes.makeMenu()
        courseModes.menuItem = modesItem
        menu.insertItem(modesItem, at: 1)

        if let index = menu.items.firstIndex(where: { $0.action == #selector(AppController.toggleWhiteboard) }),
           let whiteboard = whiteboardController {
            menu.items[index].target = whiteboard
            menu.items[index].action = #selector(WhiteboardController.toggle)
        }
        if let index = menu.items.firstIndex(where: { $0.action == #selector(AppController.toggleCaptions) }) {
            let toggleItem = menu.items[index]
            toggleItem.target = controller.captionController
            toggleItem.action = #selector(CaptionController.toggle)
            let optionsItem = NSMenuItem(title: L10n.t("Caption Options", "字幕選項"), action: nil, keyEquivalent: "")
            optionsItem.submenu = controller.captionController.makeMenu()
            menu.insertItem(optionsItem, at: index + 1)
        }
        if let index = menu.items.firstIndex(where: { $0.action == #selector(AppController.toggleSpotlight) }) {
            let toggleItem = menu.items[index]
            toggleItem.target = controller.spotlightController
            toggleItem.action = #selector(SpotlightController.toggleSpotlight)
            let optionsItem = NSMenuItem(title: L10n.t("Spotlight Options", "聚光燈選項"), action: nil, keyEquivalent: "")
            optionsItem.submenu = controller.spotlightController.makeMenu()
            menu.insertItem(optionsItem, at: index + 1)
        }

        let graphicalItem = NSMenuItem(title: L10n.t("Graphical Mode", "圖形介面模式"),
                                       action: #selector(toggleGraphicalTools(_:)), keyEquivalent: "")
        graphicalItem.target = self
        graphicalItem.image = Self.menuSymbol("square.grid.2x2")
        graphicalItem.state = UserDefaults.standard.bool(forKey: GraphicalTools.preference) ? .on : .off
        menu.insertItem(graphicalItem, at: 2)
        item.menu = menu
        return item
    }

    @objc private func toggleGraphicalTools(_ sender: NSMenuItem) {
        let enabled = sender.state != .on
        UserDefaults.standard.set(enabled, forKey: GraphicalTools.preference)
        sender.state = enabled ? .on : .off
        graphicalTools?.setVisible(enabled)
    }

    /// Menu icons are made once and reused across menu rebuilds (language
    /// changes rebuild the menu).
    private static var menuSymbolCache: [String: NSImage] = [:]

    static func menuSymbol(_ name: String?) -> NSImage? {
        guard let name else { return nil }
        if let cached = menuSymbolCache[name] { return cached }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        menuSymbolCache[name] = image
        return image
    }

    /// A single status-bar menu entry (or a separator when `action` is nil).
    struct StatusMenuEntry {
        let title: String
        let action: Selector?
        let keyEquivalent: String
        /// The SF Symbol shown beside the title; the same one Graphical Mode uses.
        let symbol: String?

        var isSeparator: Bool { action == nil }

        static let separator = StatusMenuEntry(title: "", action: nil, keyEquivalent: "")

        init(title: String, action: Selector?, keyEquivalent: String, symbol: String? = nil) {
            self.title = title
            self.action = action
            self.keyEquivalent = keyEquivalent
            self.symbol = symbol
        }
    }

    /// The status-bar menu. It broadly follows the Windows ZoomIt tray order
    /// (Options first, then the modes, then Check Permissions and Quit), with
    /// Panorama Capture as a macOS-only addition after Record and the Break
    /// Timer placed at the end of the mode group (below Panorama Capture).
    static func statusMenuEntries() -> [StatusMenuEntry] {
        [
            StatusMenuEntry(title: L10n.t("Settings…", "設定…"), action: #selector(AppController.showSettings), keyEquivalent: ",", symbol: "gearshape"),
            .separator,
            StatusMenuEntry(title: L10n.t("Draw", "畫筆"), action: #selector(AppController.activateDrawWithoutZoom), keyEquivalent: "", symbol: "pencil.tip"),
            StatusMenuEntry(title: L10n.t("Static Zoom", "靜態放大"), action: #selector(AppController.activateStaticZoom), keyEquivalent: "", symbol: "plus.magnifyingglass"),
            StatusMenuEntry(title: L10n.t("Live Zoom", "即時放大"), action: #selector(AppController.activateLiveZoom), keyEquivalent: "", symbol: "dot.viewfinder"),
            StatusMenuEntry(title: L10n.t("Record Screen", "錄製螢幕"), action: #selector(AppController.toggleRecording), keyEquivalent: "", symbol: "record.circle"),
            StatusMenuEntry(title: L10n.t("Panorama Capture", "長截圖"), action: #selector(AppController.startPanorama), keyEquivalent: "", symbol: "rectangle.split.1x2"),
            StatusMenuEntry(title: "DemoMirror", action: #selector(AppController.toggleDemoMirror), keyEquivalent: "", symbol: "rectangle.on.rectangle"),
            StatusMenuEntry(title: L10n.t("Break Timer", "休息計時器"), action: #selector(AppController.toggleBreakTimer), keyEquivalent: "", symbol: "timer"),
            StatusMenuEntry(title: L10n.t("Show Keystrokes", "顯示按鍵"), action: #selector(AppController.toggleKeystrokes), keyEquivalent: "", symbol: "command"),
            StatusMenuEntry(title: L10n.t("Spotlight", "聚光燈"), action: #selector(AppController.toggleSpotlight), keyEquivalent: "", symbol: "lightbulb"),
            StatusMenuEntry(title: L10n.t("Live Captions", "即時字幕"), action: #selector(AppController.toggleCaptions), keyEquivalent: "", symbol: "captions.bubble"),
            StatusMenuEntry(title: L10n.t("Whiteboard", "白板"), action: #selector(AppController.toggleWhiteboard), keyEquivalent: "", symbol: "rectangle.and.pencil.and.ellipsis"),
            .separator,
            StatusMenuEntry(title: L10n.t("Check Permissions", "檢查權限"), action: #selector(AppController.checkPermissions), keyEquivalent: "", symbol: "checkmark.shield"),
            StatusMenuEntry(title: L10n.t("Quit", "結束 TeachLens"), action: #selector(AppController.quit), keyEquivalent: "q", symbol: "power")
        ]
    }

    /// Loads the bundled black template version of the Windows ZoomIt icon and
    /// sizes it for the menu bar. As a template image it is tinted by the system
    /// (black on a light menu bar, white on a dark one).
    private static func menuBarIcon() -> NSImage? {
        guard let source = loadTeachLensIcon() else { return nil }
        return Self.menuBarImage(from: source)
    }

    /// The square point size of the menu-bar item's image slot.
    static let menuBarIconCanvas: CGFloat = 18
    /// The glyph is drawn smaller than the canvas so TeachLens's icon carries the
    /// same interior padding as system menu-bar icons; a full-bleed image made
    /// it look oversized and misaligned next to them.
    static let menuBarIconGlyph: CGFloat = 15

    /// Renders `source` centered inside a padded, square template image so it
    /// matches the size and vertical alignment of other menu-bar icons.
    static func menuBarImage(from source: NSImage) -> NSImage {
        let canvas = NSSize(width: menuBarIconCanvas, height: menuBarIconCanvas)
        let image = NSImage(size: canvas)
        image.lockFocus()
        let rect = NSRect(
            x: (canvas.width - menuBarIconGlyph) / 2,
            y: (canvas.height - menuBarIconGlyph) / 2,
            width: menuBarIconGlyph,
            height: menuBarIconGlyph
        )
        source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private static func loadTeachLensIcon() -> NSImage? {
        TeachLensAppIcon.loadTemplateIcon()
    }
}