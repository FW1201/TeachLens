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
        try testCaptionFormats()
        try testCaptionSentenceTracker()
        try testWhiteboardPagesAndEraser()
        try testWhiteboardExportAndStore()
    }

    private static func testWhiteboardPagesAndEraser() throws {
        var doc = WhiteboardDocument()
        let stroke = WhiteboardStroke(points: [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 100)],
                                      color: WhiteboardColor.palette[1], width: 4, isHighlighter: false)
        doc.currentPage.strokes.append(stroke)
        doc.addPage()
        doc.addPage()
        try expect(doc.pages.count == 3 && doc.currentIndex == 2, "Adding pages should move to the new page")
        doc.go(-5)
        try expect(doc.currentIndex == 0, "Navigation should clamp at the first page")
        doc.erase(at: CGPoint(x: 150, y: 300), radius: 10)
        try expect(doc.currentPage.strokes.count == 1, "Erasing far away should keep the stroke")
        doc.erase(at: CGPoint(x: 150, y: 104), radius: 10)
        try expect(doc.currentPage.strokes.isEmpty, "Erasing on the stroke should remove it")
        doc.deleteCurrentPage()
        try expect(doc.pages.count == 2, "Deleting should remove a page")
    }

    private static func testWhiteboardExportAndStore() throws {
        var doc = WhiteboardDocument()
        doc.currentPage.background = .grid
        doc.currentPage.strokes.append(WhiteboardStroke(points: [CGPoint(x: 10, y: 10), CGPoint(x: 800, y: 500)],
                                                        color: WhiteboardColor.palette[2], width: 6, isHighlighter: false))
        for _ in 0..<49 { doc.addPage(after: .lines) }
        let pdf = WhiteboardRenderer.pdfData(doc)
        guard let provider = CGDataProvider(data: pdf as CFData), let parsed = CGPDFDocument(provider) else {
            throw SelfTestError.failure("Teaching: whiteboard PDF did not parse")
        }
        try expect(parsed.numberOfPages == 50, "Expected a 50-page PDF, got \(parsed.numberOfPages)")
        try expect(WhiteboardRenderer.pngData(doc.pages[0]) != nil, "PNG export should succeed")

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TeachLensSelfTest-\(UUID().uuidString)/whiteboard.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = WhiteboardStore(url: url)
        store.save(doc)
        try expect(store.load() == doc, "Whiteboard should round-trip through its store")
    }

    private static func testCaptionFormats() throws {
        let segments = [
            CaptionSegment(start: 1.5, end: 4.25, text: "大家好"),
            CaptionSegment(start: 3_661.0, end: 3_663.5, text: "Second line"),
        ]
        let srt = CaptionFormatter.srt(segments)
        try expect(srt.hasPrefix("1\n00:00:01,500 --> 00:00:04,250\n大家好\n"), "Unexpected SRT:\n\(srt)")
        try expect(srt.contains("2\n01:01:01,000 --> 01:01:03,500\nSecond line"), "Hours should be formatted")
        let vtt = CaptionFormatter.vtt(segments)
        try expect(vtt.hasPrefix("WEBVTT\n\n00:00:01.500 --> 00:00:04.250\n大家好"), "Unexpected VTT:\n\(vtt)")
        let sliced = CaptionFormatter.slice(segments, from: 2, to: 10)
        try expect(sliced.count == 1 && sliced[0].start == 0 && sliced[0].end == 2.25,
                   "Slicing should shift times to the recording start, got \(sliced)")
    }

    private static func testCaptionSentenceTracker() throws {
        var tracker = CaptionSentenceTracker()
        tracker.partial("今天", at: 10)
        tracker.partial("今天我們", at: 10.4)
        try expect(tracker.finishIfDue(at: 11) == nil, "No pause yet")
        let segment = tracker.finishIfDue(at: 11.7)
        try expect(segment == CaptionSegment(start: 10, end: 10.4, text: "今天我們"), "Pause should end the sentence, got \(String(describing: segment))")
        try expect(tracker.finishIfDue(at: 20) == nil, "Tracker should be empty after finishing")
        tracker.partial("long", at: 30)
        for i in 1...60 { tracker.partial("long \(i)", at: 30 + Double(i)) }
        try expect(tracker.finishIfDue(at: 90.5) != nil, "Long requests should rotate before the one-minute limit")
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
