import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var appController: AppController?

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

        let hotkeyService = HotkeyService(settingsStore: settingsStore) { command in
            Task { @MainActor in
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

        appController = AppController(
            settingsStore: settingsStore,
            permissionService: permissionService,
            hotkeyService: hotkeyService,
            modeCoordinator: modeCoordinator,
            userSelectedResourceAccess: userSelectedResourceAccess,
            keystrokeController: keystrokeController
        )

        statusItem = makeStatusItem(controller: appController!)
        modeCoordinator.onRecordingStateChanged = { [weak self] recording in
            self?.updateRecordingIndicator(recording)
        }
        hotkeyService.start()
        keystrokeController.start()

        // On a fresh install, open Settings so the user has a clear entry point
        // instead of a silent menu-bar-only launch (issue #21). Upgrading users
        // are detected as returning by hasCompletedFirstLaunch, so they don't get
        // an unexpected pop-up. Persist the flag either way so later launches no
        // longer depend on the legacy migration sentinel.
        if !settingsStore.hasCompletedFirstLaunch {
            appController?.showSettings()
        }
        settingsStore.markFirstLaunchCompleted()
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

    private func makeStatusItem(controller: AppController) -> NSStatusItem {
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
                menu.addItem(NSMenuItem(title: entry.title, action: entry.action, keyEquivalent: entry.keyEquivalent))
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
            let optionsItem = NSMenuItem(title: "Keystroke Options", action: nil, keyEquivalent: "")
            optionsItem.submenu = controller.keystrokeController.makeMenu()
            menu.insertItem(optionsItem, at: index + 1)
        }

        item.menu = menu
        return item
    }

    /// A single status-bar menu entry (or a separator when `action` is nil).
    struct StatusMenuEntry {
        let title: String
        let action: Selector?
        let keyEquivalent: String

        var isSeparator: Bool { action == nil }

        static let separator = StatusMenuEntry(title: "", action: nil, keyEquivalent: "")

        init(title: String, action: Selector?, keyEquivalent: String) {
            self.title = title
            self.action = action
            self.keyEquivalent = keyEquivalent
        }
    }

    /// The status-bar menu. It broadly follows the Windows ZoomIt tray order
    /// (Options first, then the modes, then Check Permissions and Quit), with
    /// Panorama Capture as a macOS-only addition after Record and the Break
    /// Timer placed at the end of the mode group (below Panorama Capture).
    static func statusMenuEntries() -> [StatusMenuEntry] {
        [
            StatusMenuEntry(title: "Settings…", action: #selector(AppController.showSettings), keyEquivalent: ","),
            .separator,
            StatusMenuEntry(title: "Draw", action: #selector(AppController.activateDrawWithoutZoom), keyEquivalent: ""),
            StatusMenuEntry(title: "Static Zoom", action: #selector(AppController.activateStaticZoom), keyEquivalent: ""),
            StatusMenuEntry(title: "Live Zoom", action: #selector(AppController.activateLiveZoom), keyEquivalent: ""),
            StatusMenuEntry(title: "Record Screen", action: #selector(AppController.toggleRecording), keyEquivalent: ""),
            StatusMenuEntry(title: "Panorama Capture", action: #selector(AppController.startPanorama), keyEquivalent: ""),
            StatusMenuEntry(title: "DemoMirror", action: #selector(AppController.toggleDemoMirror), keyEquivalent: ""),
            StatusMenuEntry(title: "Break Timer", action: #selector(AppController.toggleBreakTimer), keyEquivalent: ""),
            StatusMenuEntry(title: "Show Keystrokes", action: #selector(AppController.toggleKeystrokes), keyEquivalent: ""),
            .separator,
            StatusMenuEntry(title: "Check Permissions", action: #selector(AppController.checkPermissions), keyEquivalent: ""),
            StatusMenuEntry(title: "Quit", action: #selector(AppController.quit), keyEquivalent: "q")
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