import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var graphicalTools: GraphicalTools?
    private var statusItem: NSStatusItem?
    private var appController: AppController?
    private var courseModeController: CourseModeController?
    private var whiteboardController: WhiteboardController?
    private var languageObserver: NSObjectProtocol?
    private var classSession: ClassSession?
    private var classItem: NSMenuItem?
    private var graphicalItem: NSMenuItem?
    private var isRecording = false
    private var onboarding: OnboardingController?
    /// What was showing before "Hide overlays", to bring it back.
    private var hiddenOverlays: (keystrokes: Bool, spotlight: Bool, captions: Bool)?

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
        keystrokeController.onSettingsChange = { [weak captionController] settings in
            captionController?.avoid(keystrokes: settings)
        }
        captionController.avoid(keystrokes: keystrokeController.settings)
        modeCoordinator.onToggleHideOverlays = { [weak self, weak keystrokeController, weak spotlightController, weak captionController] in
            guard let self, let keystrokeController, let spotlightController, let captionController else { return }
            self.toggleHideOverlays(keystrokes: keystrokeController, spotlight: spotlightController, captions: captionController)
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
        courseModeController.setToolbar = { [weak self] on in
            self?.setGraphicalTools(on)
        }
        courseModeController.toolbarVisible = {
            UserDefaults.standard.bool(forKey: GraphicalTools.preference)
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
            let onboarding = OnboardingController(teaching: teaching)
            onboarding.onFinish = { [weak self] in self?.setGraphicalTools(true) }
            OnboardingController.shared = onboarding
            self.onboarding = onboarding
        }
        let classSession = ClassSession(courseModes: courseModeController, testCenter: testCenter)
        classSession.onChange = { [weak self] inClass in self?.classStateChanged(inClass) }
        classSession.openCheck = { [weak self] in self?.appController?.openSettingsPane("Check") }
        classSession.isRecording = { [weak self] in self?.isRecording ?? false }
        self.classSession = classSession

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
            self?.isRecording = recording
            self?.graphicalTools?.recording = recording
            self?.updateRecordingIndicator(recording)
            captionController?.recordingStateChanged(recording)
        }
        hotkeyService.start()
        keystrokeController.start()
        spotlightController.start()
        courseModeController.restoreLastMode()

        // On a fresh install, open the three-step guide so the user has a clear
        // entry point instead of a silent menu-bar-only launch (issue #21).
        // Upgrading users are detected as returning by hasCompletedFirstLaunch,
        // so they don't get an unexpected pop-up.
        if !settingsStore.hasCompletedFirstLaunch {
            onboarding?.show()
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
            button.contentTintColor = nil
        } else {
            button.image = Self.menuBarIcon()
            button.contentTintColor = classSession?.inClass == true ? .systemGreen : nil
        }
    }

    /// The menu-bar menu, kept short: the class switch, course modes and the
    /// toolbar on top, every tool in one Tools submenu, then Check & Test,
    /// Settings and Quit.
    private func makeStatusItem(controller: AppController, courseModes: CourseModeController) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Intentionally no autosaveName: persisting an absolute menu-bar slot makes
        // AppKit re-assert that position on every relaunch/relayout, which fights
        // menu-bar managers like Bartender and Ice. Users can still Command-drag it.
        if let button = item.button {
            if let image = Self.menuBarIcon() {
                button.image = image
            } else {
                button.title = "TeachLens"
            }
        }

        let menu = NSMenu()

        let classItem = NSMenuItem(title: "", action: #selector(toggleClass(_:)), keyEquivalent: "")
        classItem.target = self
        self.classItem = classItem
        menu.addItem(classItem)

        let modesItem = NSMenuItem(title: L10n.t("Course Mode", "課程模式"), action: nil, keyEquivalent: "")
        modesItem.image = Self.menuSymbol("square.stack")
        modesItem.submenu = courseModes.makeMenu()
        courseModes.menuItem = modesItem
        menu.addItem(modesItem)

        let graphicalItem = NSMenuItem(title: L10n.t("Floating Toolbar", "圖形工具列"),
                                       action: #selector(toggleGraphicalTools(_:)), keyEquivalent: "")
        graphicalItem.target = self
        graphicalItem.image = Self.menuSymbol("square.grid.2x2")
        graphicalItem.state = UserDefaults.standard.bool(forKey: GraphicalTools.preference) ? .on : .off
        self.graphicalItem = graphicalItem
        menu.addItem(graphicalItem)
        menu.addItem(.separator())

        // Every tool, with its options, in one submenu.
        let tools = NSMenu(title: L10n.t("Tools", "工具"))
        let skipped: Set<Selector> = [#selector(AppController.showSettings), #selector(AppController.checkPermissions),
                                      #selector(AppController.quit)]
        for entry in Self.statusMenuEntries() {
            if let action = entry.action, skipped.contains(action) { continue }
            if entry.isSeparator {
                if tools.items.last?.isSeparatorItem == false { tools.addItem(.separator()) }
                continue
            }
            let menuItem = NSMenuItem(title: entry.title, action: entry.action, keyEquivalent: entry.keyEquivalent)
            menuItem.image = Self.menuSymbol(entry.symbol)
            menuItem.target = controller
            tools.addItem(menuItem)
        }
        if tools.items.last?.isSeparatorItem == true { tools.removeItem(at: tools.items.count - 1) }

        // Keystroke overlay: the toggle shows a checkmark via the keystroke
        // controller's menu validation, followed by its options submenu.
        if let index = tools.items.firstIndex(where: { $0.action == #selector(AppController.toggleKeystrokes) }) {
            let toggleItem = tools.items[index]
            toggleItem.target = controller.keystrokeController
            toggleItem.action = #selector(KeystrokeController.toggle)
            let optionsItem = NSMenuItem(title: L10n.t("Keystroke Options", "按鍵顯示選項"), action: nil, keyEquivalent: "")
            optionsItem.image = Self.menuSymbol("slider.horizontal.3")
            optionsItem.submenu = controller.keystrokeController.makeMenu()
            tools.insertItem(optionsItem, at: index + 1)
        }
        if let index = tools.items.firstIndex(where: { $0.action == #selector(AppController.toggleWhiteboard) }),
           let whiteboard = whiteboardController {
            tools.items[index].target = whiteboard
            tools.items[index].action = #selector(WhiteboardController.toggle)
        }
        if let index = tools.items.firstIndex(where: { $0.action == #selector(AppController.toggleCaptions) }) {
            let toggleItem = tools.items[index]
            toggleItem.target = controller.captionController
            toggleItem.action = #selector(CaptionController.toggle)
            let optionsItem = NSMenuItem(title: L10n.t("Caption Options", "字幕選項"), action: nil, keyEquivalent: "")
            optionsItem.image = Self.menuSymbol("slider.horizontal.3")
            optionsItem.submenu = controller.captionController.makeMenu()
            tools.insertItem(optionsItem, at: index + 1)
        }
        if let index = tools.items.firstIndex(where: { $0.action == #selector(AppController.toggleSpotlight) }) {
            let toggleItem = tools.items[index]
            toggleItem.target = controller.spotlightController
            toggleItem.action = #selector(SpotlightController.toggleSpotlight)
            let optionsItem = NSMenuItem(title: L10n.t("Spotlight Options", "聚光燈選項"), action: nil, keyEquivalent: "")
            optionsItem.image = Self.menuSymbol("slider.horizontal.3")
            optionsItem.submenu = controller.spotlightController.makeMenu()
            tools.insertItem(optionsItem, at: index + 1)
        }
        let toolsItem = NSMenuItem(title: L10n.t("Tools", "工具"), action: nil, keyEquivalent: "")
        toolsItem.image = Self.menuSymbol("wrench.and.screwdriver")
        toolsItem.submenu = tools
        menu.addItem(toolsItem)
        menu.addItem(.separator())

        let checkItem = NSMenuItem(title: L10n.t("Check & Test…", "總覽與測試…"),
                                   action: #selector(openCheckAndTest(_:)), keyEquivalent: "")
        checkItem.target = self
        checkItem.image = Self.menuSymbol("checkmark.shield")
        menu.addItem(checkItem)
        let settingsItem = NSMenuItem(title: L10n.t("Settings…", "設定…"),
                                      action: #selector(AppController.showSettings), keyEquivalent: ",")
        settingsItem.target = controller
        settingsItem.image = Self.menuSymbol("gearshape")
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: L10n.t("Quit", "結束 TeachLens"), action: #selector(AppController.quit),
                                  keyEquivalent: "q")
        quitItem.target = controller
        quitItem.image = Self.menuSymbol("power")
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
        classStateChanged(classSession?.inClass ?? false)
        return item
    }

    /// Control+Option+Command+H: hide everything students can see at once, and
    /// bring exactly that back on the second press.
    private func toggleHideOverlays(keystrokes: KeystrokeController, spotlight: SpotlightController,
                                    captions: CaptionController) {
        if let hidden = hiddenOverlays {
            keystrokes.update { $0.enabled = hidden.keystrokes }
            spotlight.setSpotlight(hidden.spotlight)
            captions.setEnabled(hidden.captions)
            hiddenOverlays = nil
            GlassToast.shared.show(symbol: "eye", title: L10n.t("Overlays back", "已恢復畫面提示"))
        } else {
            hiddenOverlays = (keystrokes.settings.enabled, spotlight.spotlightOn, captions.isRunning)
            keystrokes.update { $0.enabled = false }
            spotlight.setSpotlight(false)
            captions.setEnabled(false)
            GlassToast.shared.show(symbol: "eye.slash", title: L10n.t("All overlays hidden", "已隱藏所有畫面提示"),
                                   message: L10n.t("Press ⌃⌥⌘H again to bring them back.", "再按 ⌃⌥⌘H 恢復。"))
        }
    }

    @objc private func toggleClass(_ sender: NSMenuItem) {
        classSession?.toggle()
    }

    @objc private func openCheckAndTest(_ sender: NSMenuItem) {
        appController?.openSettingsPane("Check")
    }

    /// Menu title and menu-bar tint follow the class state: green while in class.
    private func classStateChanged(_ inClass: Bool) {
        classItem?.title = inClass ? L10n.t("End Class", "下課") : L10n.t("Start Class", "開始上課")
        classItem?.image = Self.menuSymbol(inClass ? "stop.circle" : "play.circle")
        if !isRecording {
            statusItem?.button?.contentTintColor = inClass ? .systemGreen : nil
        }
    }

    @objc private func toggleGraphicalTools(_ sender: NSMenuItem) {
        setGraphicalTools(sender.state != .on)
    }

    /// Shows or hides the floating toolbar and remembers the choice.
    func setGraphicalTools(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: GraphicalTools.preference)
        graphicalItem?.state = enabled ? .on : .off
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