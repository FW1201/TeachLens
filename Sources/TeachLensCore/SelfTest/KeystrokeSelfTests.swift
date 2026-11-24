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
        try testModifierClickAndDrag()
        try testScrollReleasesAfterLinger()
        try testSettingsRoundTripAndDefaults()
        try testSettingsDecodeToleratesMissingKeys()
        try testKeystrokeDefaultHotkeyDoesNotCollideWithZoomIt()
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
}
