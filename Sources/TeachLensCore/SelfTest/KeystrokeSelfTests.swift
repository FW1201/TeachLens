import AppKit
import Carbon.HIToolbox

/// Self-tests for the keystroke visualization (Keyviz port).
@MainActor
enum KeystrokeSelfTests {
    static func run() throws {
        try testKeyCodeMapCoversCommonKeys()
        try testModifierFlagDecoding()
        try testDisplayOrderUsesMacModifierOrder()
        try testDisplayGroupMergesModifierGlyphs()
        try testShortcutFilterHidesPlainTyping()
        try testCombinationBuildsOneGroup()
        try testRepeatedKeyBumpsCount()
        try testReplaceModeKeepsOneGroup()
        try testHistoryModeKeepsRecentGroups()
        try testReleasedKeysExpireAfterLinger()
        try testHeldKeysDoNotExpire()
        try testSoloModifierWaitsBeforeShowing()
        try testCombinationExpiresAsAWhole()
        try testReleasedKeyLeavesCombination()
        try testWindowsFirstPill()
        try testMeetingBarAndCaptionClearance()
        try testModifierClickAndDrag()
        try testScrollReleasesAfterLinger()
        try testSettingsRoundTripAndDefaults()
        try testSettingsDecodeToleratesMissingKeys()
        try testKeystrokeDefaultHotkeyDoesNotCollideWithZoomIt()
        try testHotkeyConflictDetection()
        try testRecordingCompositePlacesHUD()
        try testCustomShortcuts()
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw SelfTestError.failure("Keystroke: " + message) }
    }

    private static func engine(_ change: (inout KeystrokeEngineConfig) -> Void = { _ in }) -> KeystrokeEngine {
        var config = KeystrokeEngineConfig()
        change(&config)
        return KeystrokeEngine(config: config)
    }

    private static func names(_ group: KeystrokeGroup?) -> [String] {
        group?.keys.map(\.name) ?? []
    }

    private static func testKeyCodeMapCoversCommonKeys() throws {
        try expect(KeyCodeMap.name(for: kVK_ANSI_A) == "KeyA", "kVK_ANSI_A should map to KeyA")
        try expect(KeyCodeMap.name(for: kVK_ANSI_0) == "Num0", "kVK_ANSI_0 should map to Num0")
        try expect(KeyCodeMap.name(for: kVK_Command) == KeyName.metaLeft, "Left Command should map to MetaLeft")
        try expect(KeyCodeMap.name(for: kVK_RightOption) == KeyName.alt, "Right Option should map to Alt")
        try expect(KeyCodeMap.name(for: kVK_F12) == "F12", "F12 should map to F12")
        try expect(KeyCodeMap.name(for: kVK_Delete) == "Backspace", "Delete should map to Backspace")
        for code in KeyCodeMap.table.keys {
            let name = KeyCodeMap.table[code]!
            let display = KeyDisplayMap.display(for: name)
            try expect(display.category != .other, "Key \(name) (\(code)) has no display entry")
        }
    }

    private static func testModifierFlagDecoding() throws {
        let leftCommandDown: UInt64 = 0x0010_0008
        try expect(KeyCodeMap.isModifierDown(keyCode: kVK_Command, flags: leftCommandDown) == true, "Left command should be down")
        try expect(KeyCodeMap.isModifierDown(keyCode: kVK_RightCommand, flags: leftCommandDown) == false, "Right command should be up")
        try expect(KeyCodeMap.isModifierDown(keyCode: kVK_Shift, flags: 0x100) == false, "Shift should be up with no device bits")
        try expect(KeyCodeMap.isModifierDown(keyCode: kVK_ANSI_A, flags: 0) == nil, "A letter is not a modifier")
    }

    private static func testDisplayOrderUsesMacModifierOrder() throws {
        let ordered = KeyName.displayOrder([KeyName.metaLeft, "KeyS", KeyName.shiftLeft, KeyName.controlLeft, KeyName.alt])
        try expect(ordered == [KeyName.controlLeft, KeyName.alt, KeyName.shiftLeft, KeyName.metaLeft, "KeyS"],
                   "Expected ⌃⌥⇧⌘ order, got \(ordered)")
    }

    private static func testDisplayGroupMergesModifierGlyphs() throws {
        let group = KeystrokeGroup(keys: [
            KeystrokeKey(name: KeyName.metaLeft, at: 0),
            KeystrokeKey(name: KeyName.shiftLeft, at: 0),
            KeystrokeKey(name: "Num4", at: 0)
        ], createdAt: 0)
        let display = KeystrokeDisplayGroup.make(from: group, index: 0)
        try expect(display.modifierGlyphs == "⇧⌘", "Expected merged glyphs ⇧⌘, got \(display.modifierGlyphs)")
        try expect(display.chips.map(\.text) == ["4"], "Expected a single 4 chip, got \(display.chips.map(\.text))")
    }

    private static func testShortcutFilterHidesPlainTyping() throws {
        var e = engine()
        e.keyDown("KeyH", at: 0)
        e.keyUp("KeyH", at: 0.05)
        try expect(e.groups.isEmpty, "Plain typing should be hidden in shortcuts-only mode")
        var all = engine { $0.filter = .none }
        all.keyDown("KeyH", at: 0)
        try expect(names(all.groups.last) == ["KeyH"], "Plain typing should show when the filter is off")
    }

    private static func testCombinationBuildsOneGroup() throws {
        var e = engine()
        e.keyDown(KeyName.metaLeft, at: 0)
        e.keyDown(KeyName.shiftLeft, at: 0.01)
        e.keyDown("Num4", at: 0.02)
        try expect(e.groups.count == 1, "Expected one group, got \(e.groups.count)")
        try expect(names(e.groups.first) == [KeyName.metaLeft, KeyName.shiftLeft, "Num4"], "Unexpected group \(names(e.groups.first))")
    }

    private static func testRepeatedKeyBumpsCount() throws {
        var e = engine()
        e.keyDown(KeyName.metaLeft, at: 0)
        for i in 0..<3 {
            e.keyDown("KeyZ", at: 0.1 + Double(i) * 0.1)
            e.keyUp("KeyZ", at: 0.15 + Double(i) * 0.1)
        }
        try expect(e.groups.count == 1, "Expected one group for ⌘Z ×3")
        try expect(e.groups[0].keys.last?.pressedCount == 3, "Expected Z pressed 3 times, got \(e.groups[0].keys.last?.pressedCount ?? 0)")
    }

    private static func testReplaceModeKeepsOneGroup() throws {
        var e = engine()
        e.keyDown(KeyName.metaLeft, at: 0)
        e.keyDown("KeyC", at: 0.1)
        e.keyUp("KeyC", at: 0.2)
        e.keyUp(KeyName.metaLeft, at: 0.3)
        e.keyDown(KeyName.metaLeft, at: 1)
        e.keyDown("KeyV", at: 1.1)
        try expect(e.groups.count == 1, "Replace mode should show one group")
        try expect(names(e.groups.first) == [KeyName.metaLeft, "KeyV"], "Expected ⌘V, got \(names(e.groups.first))")
    }

    private static func testHistoryModeKeepsRecentGroups() throws {
        var e = engine { $0.showHistory = true; $0.maxHistory = 2 }
        for (i, key) in ["KeyA", "KeyB", "KeyC"].enumerated() {
            let t = Double(i)
            e.keyDown(KeyName.metaLeft, at: t)
            e.keyDown(key, at: t + 0.1)
            e.keyUp(key, at: t + 0.2)
            e.keyUp(KeyName.metaLeft, at: t + 0.3)
        }
        try expect(e.groups.count == 2, "History should keep 2 groups, got \(e.groups.count)")
        try expect(names(e.groups.last) == [KeyName.metaLeft, "KeyC"], "Newest group should be ⌘C, got \(names(e.groups.last))")
    }

    private static func testReleasedKeysExpireAfterLinger() throws {
        var e = engine { $0.lingerDuration = 1 }
        e.keyDown(KeyName.metaLeft, at: 0)
        e.keyDown("KeyS", at: 0.1)
        e.keyUp("KeyS", at: 0.2)
        e.keyUp(KeyName.metaLeft, at: 0.2)
        try expect(!e.tick(at: 0.5), "Nothing should expire before the linger time")
        try expect(e.tick(at: 1.5), "Keys should expire after the linger time")
        try expect(e.groups.isEmpty, "All groups should be gone")
    }

    private static func testSoloModifierWaitsBeforeShowing() throws {
        // Typing ⌘C quickly never shows a lone ⌘ first.
        var e = engine()
        e.keyDown(KeyName.metaLeft, at: 0)
        try expect(e.visibleGroups(at: 0.1).isEmpty, "A just-pressed ⌘ should not show yet")
        e.keyDown("KeyC", at: 0.12)
        try expect(names(e.visibleGroups(at: 0.12).last) == [KeyName.metaLeft, "KeyC"], "⌘C should show at once")

        // A quick tap of ⌘ on its own shows nothing at all.
        var tap = engine()
        tap.keyDown(KeyName.metaLeft, at: 0)
        tap.keyUp(KeyName.metaLeft, at: 0.1)
        try expect(tap.visibleGroups(at: 0.2).isEmpty, "A quick ⌘ tap should not show")

        // Holding ⌥ to explain it shows it, briefly after release, then hides.
        var hold = engine { $0.lingerDuration = 3 }
        hold.keyDown(KeyName.alt, at: 0)
        try expect(names(hold.visibleGroups(at: 0.5).last) == [KeyName.alt], "A held ⌥ should show")
        hold.keyUp(KeyName.alt, at: 1.0)
        try expect(!hold.visibleGroups(at: 1.5).isEmpty, "A held ⌥ should stay briefly after release")
        try expect(hold.visibleGroups(at: 2.5).isEmpty, "A lone ⌥ should not use the full linger time")
    }

    private static func testCombinationExpiresAsAWhole() throws {
        var e = engine { $0.lingerDuration = 1 }
        e.keyDown(KeyName.metaLeft, at: 0)
        e.keyDown("KeyZ", at: 0.1)
        e.keyUp("KeyZ", at: 0.2)
        e.tick(at: 5)
        try expect(names(e.visibleGroups(at: 5).last) == [KeyName.metaLeft, "KeyZ"],
                   "Holding ⌘ after ⌘Z should keep ⌘Z, got \(names(e.visibleGroups(at: 5).last))")
        e.keyUp(KeyName.metaLeft, at: 5)
        e.tick(at: 5.5)
        try expect(!e.groups.isEmpty, "The combination should linger after release")
        e.tick(at: 6.5)
        try expect(e.groups.isEmpty, "The combination should leave together")
    }

    private static func testMeetingBarAndCaptionClearance() throws {
        var settings = KeystrokeSettings()
        settings.position = .bottomCenter
        try expect(settings.avoidMeetingBar && settings.meetingInset == KeystrokeSettings.meetingBarHeight,
                   "Bottom pills should keep clear of the meeting bar by default")
        settings.position = .topCenter
        try expect(settings.meetingInset == 0, "Top pills need no meeting-bar room")
        settings.position = .bottomCenter
        let plain = settings.occupiedHeight
        settings.windowsEquivalent = true
        try expect(settings.occupiedHeight > plain, "The Windows line should take more room")
        settings.enabled = false
        try expect(settings.occupiedHeight == 0, "Hidden keystrokes take no room")
        try expect(KeystrokeSizePreset(rawValue: KeystrokeSettings().scale) == .normal,
                   "The default size should be the Standard preset")
        try expect(WindowsEquivalent.cheatSheet.count >= 20, "The handout should list the common shortcuts")
    }

    private static func testWindowsFirstPill() throws {
        func display(_ names: [String]) -> KeystrokeDisplayGroup {
            var e = engine { $0.filter = .none }
            for (i, name) in names.enumerated() { e.keyDown(name, at: Double(i) * 0.01) }
            return KeystrokeDisplayGroup.make(from: e.groups.last!, index: 0)
        }
        let copy = display([KeyName.metaLeft, "KeyC"])
        guard let win = copy.windowsPrimary() else { throw SelfTestError.failure("Keystroke: ⌘C should have a Windows pill") }
        try expect(win.modifierGlyphs == "Ctrl" && win.chips.map(\.text) == ["C"] && win.modifiersAreWords,
                   "⌘C should read Ctrl + C, got \(win.modifierGlyphs) \(win.chips.map(\.text))")
        try expect(copy.macText == "⌘C", "The Mac line for ⌘C should be ⌘C, got \(copy.macText)")

        let snip = display([KeyName.shiftLeft, KeyName.metaLeft, "Num4"])
        let snipWin = snip.windowsPrimary()
        try expect(snipWin?.modifierGlyphs == "⊞ Win + Shift" && snipWin?.chips.map(\.text) == ["S"],
                   "⇧⌘4 should read ⊞ Win + Shift + S, got \(String(describing: snipWin?.modifierGlyphs))")
        try expect(snip.macText == "⇧⌘4", "The Mac line for ⇧⌘4 should be ⇧⌘4, got \(snip.macText)")

        try expect(display(["KeyA"]).windowsPrimary() == nil, "A plain letter is the same on both systems")

        let decoded = try JSONDecoder().decode(KeystrokeSettings.self, from: Data("{}".utf8))
        try expect(decoded.primaryPlatform == .mac, "Existing settings should stay Mac first")
    }

    private static func testReleasedKeyLeavesCombination() throws {
        var e = engine()
        e.keyDown(KeyName.metaLeft, at: 0)
        e.keyDown("KeyZ", at: 0.1)
        e.keyUp("KeyZ", at: 0.2)
        e.keyDown("KeyX", at: 0.4)
        try expect(names(e.groups.last) == [KeyName.metaLeft, "KeyX"],
                   "Hold ⌘, Z, then X should show ⌘X, got \(names(e.groups.last))")
    }

    private static func testHeldKeysDoNotExpire() throws {
        var e = engine { $0.lingerDuration = 1 }
        e.keyDown(KeyName.metaLeft, at: 0)
        e.tick(at: 10)
        try expect(names(e.groups.last) == [KeyName.metaLeft], "A held key should stay visible")
    }

    private static func testModifierClickAndDrag() throws {
        var e = engine()
        e.keyDown(KeyName.alt, at: 0)
        e.mouseDown(KeyName.mouseLeft, x: 100, y: 100, at: 0.1)
        try expect(names(e.groups.last) == [KeyName.alt, KeyName.mouseLeft], "Expected ⌥ + click, got \(names(e.groups.last))")
        e.mouseMoved(x: 200, y: 100, at: 0.2)
        try expect(names(e.groups.last) == [KeyName.alt, KeyName.drag], "Expected ⌥ + drag, got \(names(e.groups.last))")
        e.mouseUp(KeyName.mouseLeft, at: 0.3)
        try expect(!e.isPressed(KeyName.drag), "Drag should be released")

        var plain = engine()
        plain.mouseDown(KeyName.mouseLeft, x: 0, y: 0, at: 0)
        try expect(plain.groups.isEmpty, "A lone click is not a shortcut")
    }

    private static func testScrollReleasesAfterLinger() throws {
        var e = engine { $0.filter = .none }
        e.scroll(deltaY: 3, at: 0)
        try expect(e.isPressed(KeyName.scrollUp), "Scrolling up should press ScrollUp")
        e.scroll(deltaY: -2, at: 0.1)
        try expect(!e.isPressed(KeyName.scrollUp) && e.isPressed(KeyName.scrollDown), "Reversing should switch to ScrollDown")
        e.tick(at: 0.5)
        try expect(!e.isPressed(KeyName.scrollDown), "Scroll should release after it stops")
    }

    private static func testSettingsRoundTripAndDefaults() throws {
        let suite = "TeachLensSelfTest.Keystroke.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw SelfTestError.failure("Could not create defaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = KeystrokeSettingsStore(defaults: defaults)
        let initial = store.load()
        try expect(initial == KeystrokeSettings(), "Missing settings should load defaults")
        try expect(initial.position == .bottomCenter && initial.glass == .automatic, "Unexpected defaults")
        var changed = initial
        changed.position = .topRight
        changed.showHistory = true
        changed.glass = .solid
        changed.scale = 1.5
        store.save(changed)
        try expect(store.load() == changed, "Settings should round-trip")
    }

    private static func testSettingsDecodeToleratesMissingKeys() throws {
        let json = #"{"position":"topLeft","unknownFutureKey":1,"glass":"notAGlass"}"#
        let decoded = try JSONDecoder().decode(KeystrokeSettings.self, from: Data(json.utf8))
        try expect(decoded.position == .topLeft, "Known keys should decode")
        try expect(decoded.glass == .automatic, "Unknown enum values should fall back to the default")
        try expect(decoded.enabled == true && decoded.filter == .modifiers, "Missing keys should use defaults")
    }

    private static func testKeystrokeDefaultHotkeyDoesNotCollideWithZoomIt() throws {
        let keystroke = KeystrokeSettings()
        let control = NSEvent.ModifierFlags.control.rawValue
        try expect(keystroke.toggleKeyCode == kVK_ANSI_0 && keystroke.toggleModifiers == control,
                   "Default keystroke toggle should be Control+0")
        let app = AppSettings.defaults
        let used: [(Int, UInt)] = [
            (app.hotKeyCode, app.hotKeyModifiers), (app.drawHotKeyCode, app.drawHotKeyModifiers),
            (app.liveHotKeyCode, app.liveHotKeyModifiers), (app.snipHotKeyCode, app.snipHotKeyModifiers),
            (app.recordHotKeyCode, app.recordHotKeyModifiers), (app.panoramaHotKeyCode, app.panoramaHotKeyModifiers),
            (app.demoMirrorHotKeyCode, app.demoMirrorHotKeyModifiers), (app.breakHotKeyCode, app.breakHotKeyModifiers)
        ]
        for (code, modifiers) in used {
            try expect(!(code == keystroke.toggleKeyCode && modifiers == keystroke.toggleModifiers),
                       "Control+0 collides with an existing default hotkey")
        }
    }

    private static func testHotkeyConflictDetection() throws {
        let app = AppSettings.defaults
        let control = NSEvent.ModifierFlags.control.rawValue
        let shift = NSEvent.ModifierFlags.shift.rawValue
        try expect(HotkeyConflicts.conflict(keyCode: kVK_ANSI_0, modifiers: control, app: app, ignoring: "Show Keystrokes") == nil,
                   "Control+0 should be free apart from the keystroke toggle itself")
        try expect(HotkeyConflicts.conflict(keyCode: kVK_ANSI_0, modifiers: control | shift, app: app) == "Spotlight",
                   "Control+Shift+0 should belong to the spotlight")
        try expect(HotkeyConflicts.conflict(keyCode: app.hotKeyCode, modifiers: app.hotKeyModifiers, app: app) == "Static Zoom",
                   "The zoom shortcut should be reported as taken")
        try expect(HotkeyConflicts.conflict(keyCode: app.recordHotKeyCode, modifiers: app.recordHotKeyModifiers | shift, app: app) == "Record Region",
                   "Derived Shift variants should be checked too")
        try expect(HotkeyConflicts.displayString(keyCode: kVK_ANSI_0, modifiers: control) == "⌃0",
                   "Expected ⌃0, got \(HotkeyConflicts.displayString(keyCode: kVK_ANSI_0, modifiers: control))")
    }

    /// The HUD image must land where it sits on screen when composited into an
    /// overlay-rendered recording frame.
    private static func testRecordingCompositePlacesHUD() throws {
        let display = DisplayDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 80), scaleFactor: 1)
        func solid(_ width: Int, _ height: Int, _ rgba: (UInt8, UInt8, UInt8, UInt8)) throws -> CGImage {
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            for i in stride(from: 0, to: pixels.count, by: 4) {
                pixels[i] = rgba.0; pixels[i + 1] = rgba.1; pixels[i + 2] = rgba.2; pixels[i + 3] = rgba.3
            }
            guard let provider = CGDataProvider(data: Data(pixels) as CFData),
                  let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
                throw SelfTestError.failure("Could not build test image")
            }
            return image
        }
        let base = try solid(100, 80, (0, 0, 0, 255))
        let hud = try solid(20, 10, (255, 255, 255, 255))
        // Bottom-left corner of the screen in AppKit coordinates (origin bottom-left).
        let frame = KeystrokeRecordingFrame(image: hud, frame: CGRect(x: 10, y: 5, width: 20, height: 10))
        let out = RecordingController.composite(frame, over: base, display: display, sourceRect: nil)
        guard let data = out.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
            throw SelfTestError.failure("Could not read composited image")
        }
        func brightness(x: Int, yFromTop: Int) -> Int {
            let offset = yFromTop * out.bytesPerRow + x * 4
            return Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2])
        }
        // Image rows run top to bottom: the HUD covers rows 65..<75 and columns 10..<30.
        try expect(brightness(x: 20, yFromTop: 70) > 600, "HUD should be drawn near the bottom-left")
        try expect(brightness(x: 20, yFromTop: 10) < 30, "Top of the frame should stay untouched")
        try expect(brightness(x: 60, yFromTop: 70) < 30, "Area right of the HUD should stay untouched")
    }

    private static func testCustomShortcuts() throws {
        var settings = KeystrokeSettings()
        try expect(settings.customShortcuts.isEmpty, "No custom shortcuts by default")
        settings.customShortcuts = [
            CustomShortcut(keys: ["KeyB"], label: "筆刷"),
            CustomShortcut(keys: [KeyName.metaLeft, "KeyK"], label: "插入連結", windows: "Ctrl + K")
        ]
        let config = settings.engineConfig
        try expect(config.extraKeys == ["KeyB"], "Only keys without a modifier lead, got \(config.extraKeys)")

        // A single key the teacher added shows even in "Shortcuts only".
        var e = KeystrokeEngine(config: config)
        e.keyDown("KeyB", at: 0)
        try expect(names(e.groups.last) == ["KeyB"], "Custom single key B should show, got \(names(e.groups.last))")
        var plain = KeystrokeEngine(config: config)
        plain.keyDown("KeyH", at: 0)
        try expect(plain.groups.isEmpty, "Other plain keys stay hidden")

        // Caption and Windows override; right Command counts as Command.
        let group = KeystrokeGroup(keys: [
            KeystrokeKey(name: KeyName.metaRight, at: 0),
            KeystrokeKey(name: "KeyK", at: 0)
        ], createdAt: 0)
        let display = KeystrokeDisplayGroup.make(from: group, index: 0, custom: settings.customShortcuts)
        try expect(display.customLabel == "插入連結", "Expected the caption, got \(display.customLabel ?? "nil")")
        try expect(display.windowsText == "Ctrl + K", "Expected the Windows override, got \(display.windowsText ?? "nil")")
        try expect(display.windowsPrimary()?.customLabel == "插入連結", "Windows-first keeps the caption")
        let other = KeystrokeDisplayGroup.make(from: group, index: 0)
        try expect(other.customLabel == nil, "No caption without custom shortcuts")

        try expect(settings.customShortcuts[1].displayText == "⌘K", "Expected ⌘K, got \(settings.customShortcuts[1].displayText)")
        try expect(KeyComboRecorder.keys(keyCode: kVK_ANSI_K, flags: NSEvent.ModifierFlags.command.rawValue) == [KeyName.metaLeft, "KeyK"],
                   "Recorder should record ⌘K")
        try expect(KeyComboRecorder.keys(keyCode: kVK_F5, flags: 0) == ["F5"], "Recorder should accept F5 alone")
        try expect(KeyComboRecorder.keys(keyCode: kVK_Shift, flags: 0) == nil, "A bare modifier is not a shortcut")

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(KeystrokeSettings.self, from: data)
        try expect(decoded.customShortcuts == settings.customShortcuts, "Custom shortcuts should round-trip")
    }
}
