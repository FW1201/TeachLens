import AppKit

/// Self-tests for TeachLens's teaching features beyond keystrokes.
@MainActor
enum TeachingSelfTests {
    static func run() throws {
        try testShakeDetector()
        try testSpotlightPathContainsPointer()
        try testSpotlightSettingsDecode()
        try testCourseModeBuiltIns()
        try testCourseModeImportExport()
        try testWindowsEquivalents()
    }

    private static func testWindowsEquivalents() throws {
        func w(_ names: [String]) -> String? { WindowsEquivalent.text(for: names) }
        let cmd = KeyName.metaLeft, shift = KeyName.shiftLeft, opt = KeyName.alt, ctrl = KeyName.controlLeft
        let cases: [([String], String?)] = [
            ([cmd, "KeyC"], "Ctrl + C"),
            ([cmd, shift, "KeyZ"], "Ctrl + Y"),
            ([shift, cmd, "KeyS"], "Ctrl + Shift + S"),
            ([cmd, "KeyQ"], "Alt + F4"),
            ([cmd, "Tab"], "Alt + Tab"),
            ([opt, cmd, "Escape"], "Ctrl + Alt + Delete"),
            ([cmd, shift, "Num4"], "⊞ Win + Shift + S"),
            ([cmd, "LeftArrow"], "Home"),
            ([opt, "LeftArrow"], "Ctrl + ←"),
            ([opt, "KeyE"], "Alt + E"),
            ([ctrl, KeyName.mouseLeft], "Right-click"),
            (["Return"], "Enter"),
            (["KeyA"], nil),
        ]
        for (names, expected) in cases {
            try expect(w(names) == expected, "Windows equivalent of \(names) should be \(expected ?? "nil"), got \(w(names) ?? "nil")")
        }
    }

    private static func testCourseModeBuiltIns() throws {
        let modes = CourseMode.builtIns
        try expect(Set(modes.map(\.id)) == CourseMode.builtInIDs, "Expected the four built-in modes")
        try expect(modes.first { $0.id == "focus" }?.spotlight == true, "Focus mode should turn on the spotlight")
        try expect(modes.first { $0.id == "break" }?.startBreakTimer == true, "Break mode should start the break timer")
        for mode in modes {
            try expect(NSImage(systemSymbolName: mode.symbol, accessibilityDescription: nil) != nil,
                       "Mode \(mode.id) has an unknown symbol \(mode.symbol)")
        }
    }

    private static func testCourseModeImportExport() throws {
        let custom = CourseMode(id: "custom-1", name: "Lab", keystrokes: true, keystrokeFilter: .none, spotlight: true)
        let data = try CourseModeStore.encode(CourseMode.builtIns + [custom])
        let decoded = try CourseModeStore.decode(data)
        try expect(decoded.count == 5, "Expected five modes back, got \(decoded.count)")
        try expect(decoded.allSatisfy { !$0.isBuiltIn }, "Imported modes must never replace built-in ids")
        try expect(decoded.last?.name == "Lab" && decoded.last?.id == "custom-1" && decoded.last?.spotlight == true,
                   "Custom mode should round-trip")
        let bare = try CourseModeStore.decode(Data(#"[{"id":"x","name":"Bare"}]"#.utf8))
        try expect(bare.first?.keystrokes == true && bare.first?.captions == false, "Missing fields should use defaults")

        let suite = "TeachLensSelfTest.Modes.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw SelfTestError.failure("defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CourseModeStore(defaults: defaults)
        store.saveCustomModes(CourseMode.builtIns + [custom])
        try expect(store.customModes() == [custom], "Only custom modes should be stored")
        store.currentModeID = "focus"
        try expect(store.currentModeID == "focus", "Current mode should persist")
    }

    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw SelfTestError.failure("Teaching: " + message) }
    }

    private static func testShakeDetector() throws {
        var detector = ShakeDetector()
        var fired = false
        var t: TimeInterval = 0
        // Back-and-forth 80 pt swings, 50 ms apart.
        for i in 0..<12 {
            let x = i.isMultiple(of: 2) ? 100.0 : 180.0
            for step in 0..<4 {
                let from = i.isMultiple(of: 2) ? 180.0 : 100.0
                let value = from + (x - from) * Double(step + 1) / 4
                if detector.add(x: value, at: t) { fired = true }
                t += 0.012
            }
        }
        try expect(fired, "A quick back-and-forth shake should be recognised")

        var calm = ShakeDetector()
        var calmFired = false
        for i in 0..<200 {
            if calm.add(x: Double(i) * 2, at: Double(i) * 0.016) { calmFired = true }
        }
        try expect(!calmFired, "Steady movement in one direction is not a shake")
    }

    private static func testSpotlightPathContainsPointer() throws {
        let center = CGPoint(x: 300, y: 200)
        let circle = SpotlightController.spotlightPath(center: center, radius: 100, shape: .circle)
        try expect(circle.contains(center), "The lit circle should contain the pointer")
        try expect(!circle.contains(CGPoint(x: 420, y: 200)), "Points beyond the radius stay dimmed")
        let bar = SpotlightController.spotlightPath(center: center, radius: 100, shape: .bar)
        try expect(bar.contains(CGPoint(x: 480, y: 200)), "The wide bar should reach further sideways")
        try expect(!bar.contains(CGPoint(x: 300, y: 280)), "The wide bar should be short vertically")
    }

    private static func testSpotlightSettingsDecode() throws {
        let decoded = try JSONDecoder().decode(SpotlightSettings.self, from: Data(#"{"radius":220,"shape":"bar"}"#.utf8))
        try expect(decoded.radius == 220 && decoded.shape == .bar, "Known keys should decode")
        try expect(decoded.dimming == SpotlightSettings().dimming, "Missing keys should use defaults")
    }
}
