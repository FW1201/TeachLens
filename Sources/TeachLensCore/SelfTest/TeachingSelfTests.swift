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
        try testLanguageSetting()
        try testSettingsPaneTitles()
        try testKeystrokeDemoSequence()
        try testBuildCommitFallback()
        try testShortcutDescriptions()
        try testGraphicalToolsLayout()
        try testWhiteboardScreenshotScaling()
        try testWhiteboardUndoSkipsNoOps()
        try testWhiteboardShapesAndPages()
        try testSettingsGroups()
    }

    private static func testSettingsGroups() throws {
        let groups = SettingsWindowController.paneGroups
        try expect(groups.count <= 8, "Settings should show at most eight groups, got \(groups.count)")
        let members = groups.flatMap(\.members)
        try expect(Set(members) == Set(SettingsWindowController.settingsTabTitles) && members.count == Set(members).count,
                   "Every settings pane should belong to exactly one group")
        for group in groups {
            let symbol = SettingsWindowController.paneSymbolName(for: group.id)
            try expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil,
                       "Group \(group.id) needs a resolvable SF Symbol, got \(symbol)")
        }
        try expect(groups.first?.id == "Check", "Check & Test should stay first")
    }

    private static func testWhiteboardShapesAndPages() throws {
        // Boards saved before shapes existed still load.
        let old = Data(#"{"points":[[1,2]],"color":{"r":0,"g":0,"b":0},"width":4,"isHighlighter":false}"#.utf8)
        let stroke = try JSONDecoder().decode(WhiteboardStroke.self, from: old)
        try expect(stroke.kind == .free, "Whiteboard: old strokes should load as free strokes")

        var document = WhiteboardDocument()
        let box = WhiteboardStroke(points: [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 200)],
                                   color: WhiteboardColor.palette[0], width: 4, isHighlighter: false, kind: .rectangle)
        document.currentPage.strokes = [box]
        document.erase(at: CGPoint(x: 200, y: 150), radius: 10)
        try expect(document.currentPage.strokes.count == 1, "Whiteboard: erasing inside a box should not hit its outline")
        document.erase(at: CGPoint(x: 200, y: 100), radius: 10)
        try expect(document.currentPage.strokes.isEmpty, "Whiteboard: erasing on the box edge should remove it")

        document.addPage()
        document.addPage()
        document.currentIndex = 0
        document.movePage(from: 0, by: 2)
        try expect(document.currentIndex == 2, "Whiteboard: the moved current page should stay current")
    }

    private static func testWhiteboardScreenshotScaling() throws {
        let width = WhiteboardController.maxScreenshotWidth * 2, height = 1200
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = context.makeImage(),
              let png = WhiteboardController.storablePNG(image),
              let rep = NSBitmapImageRep(data: png) else { throw SelfTestError.failure("Whiteboard: screenshot PNG") }
        try expect(rep.pixelsWide == WhiteboardController.maxScreenshotWidth && rep.pixelsHigh == height / 2,
                   "Whiteboard: large screenshots should be scaled to the stored width, got \(rep.pixelsWide)×\(rep.pixelsHigh)")
    }

    private static func testWhiteboardUndoSkipsNoOps() throws {
        let model = WhiteboardModel(document: WhiteboardDocument())
        model.checkpoint()
        model.discardCheckpointIfUnchanged()
        try expect(!model.canUndo, "Whiteboard: a gesture that changed nothing should not use an undo step")
        model.checkpoint()
        model.document.currentPage.strokes.append(
            WhiteboardStroke(points: [.zero], color: WhiteboardColor.palette[0], width: 4, isHighlighter: false))
        model.discardCheckpointIfUnchanged()
        try expect(model.canUndo, "Whiteboard: a real change should keep its undo step")
        model.undo()
        try expect(model.document.currentPage.strokes.isEmpty && !model.canUndo, "Whiteboard: undo should restore the page")
    }

    private static func testGraphicalToolsLayout() throws {
        let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let home = GraphicalToolsLayout.defaultOrigin(in: screen)
        try expect(home.x + GraphicalToolsLayout.width <= screen.maxX && home.y >= screen.minY,
                   "The launcher should dock inside the bottom-right corner")
        let offRight = GraphicalToolsLayout.clampedOrigin(CGPoint(x: 5000, y: -300), in: screen)
        let inset = GraphicalToolsLayout.edgeInset
        try expect(offRight.x == screen.maxX - GraphicalToolsLayout.width - inset && offRight.y == screen.minY + inset,
                   "A launcher dragged off screen should be pulled back inside, clear of the edge")
        let tooHigh = GraphicalToolsLayout.clampedOrigin(CGPoint(x: 100, y: screen.maxY), in: screen)
        try expect(screen.maxY - tooHigh.y >= GraphicalToolsLayout.minimumRoomAbove,
                   "The launcher should keep room above it to open the column")
        // On a tall screen the open panel is exactly as tall as its content:
        // launcher + gap + column, with no empty glass.
        let items = ToolbarTool.defaultPinned.count + 1
        let wanted = GraphicalToolsLayout.collapsedHeight(scale: 1) + GraphicalToolsLayout.columnGap
            + GraphicalToolsLayout.columnHeight(items: items, scale: 1)
        try expect(GraphicalToolsLayout.expandedHeight(originY: home.y, in: screen, items: items, scale: 1) == wanted,
                   "The open toolbar should fit its six tools without empty space")
        try expect(wanted < 400, "Six tools should need well under 400 pt, got \(wanted)")
        for size in ToolbarSize.allCases {
            let scale = size.scale
            let available = GraphicalToolsLayout.columnHeight(items: items, scale: scale)
                - GraphicalToolsLayout.columnPadding
                - CGFloat(items) * (TeachLensChrome.iconHeight * scale + GraphicalToolsLayout.rowSpacing)
            try expect(abs(available - 24 * scale) < 0.001,
                       "The eye marker should have a 24 pt row that scales with toolbar size")
        }
        // Large buttons make it taller and wider; small ones smaller.
        let large = GraphicalToolsLayout.expandedHeight(originY: home.y, in: screen, items: items, scale: ToolbarSize.large.scale)
        let small = GraphicalToolsLayout.expandedHeight(originY: home.y, in: screen, items: items, scale: ToolbarSize.small.scale)
        try expect(small < wanted && wanted < large, "Toolbar height should follow the button size")
        try expect(GraphicalToolsLayout.width(scale: ToolbarSize.large.scale) > GraphicalToolsLayout.width,
                   "Large buttons need a wider toolbar")
        let short = CGRect(x: 0, y: 0, width: 800, height: 300)
        let low = GraphicalToolsLayout.clampedOrigin(CGPoint(x: 0, y: 200), in: short)
        let height = GraphicalToolsLayout.expandedHeight(originY: low.y, in: short)
        try expect(low.y + height <= short.maxY && height >= GraphicalToolsLayout.collapsedHeight,
                   "On a short screen the column should stay on screen and scroll")
        try expect(ToolbarTool.defaultPinned.count == 6 && Set(ToolbarTool.defaultPinned).count == 6,
                   "The toolbar should pin six distinct tools by default")
    }

    private static func testLanguageSetting() throws {
        let suite = "TeachLensSelfTest.Language.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw SelfTestError.failure("defaults") }
        let previousDefaults = L10n.defaults, previousForced = L10n.forcedLanguage
        defer {
            L10n.defaults = previousDefaults
            L10n.forcedLanguage = previousForced
            defaults.removePersistentDomain(forName: suite)
        }
        L10n.defaults = defaults
        L10n.forcedLanguage = nil
        try expect(L10n.language == .system, "Language should default to the system language")
        L10n.language = .zhHant
        try expect(L10n.isChinese && L10n.t("Zoom", "放大") == "放大", "Traditional Chinese should be used when chosen")
        L10n.language = .en
        try expect(!L10n.isChinese && L10n.t("Zoom", "放大") == "Zoom", "English should be used when chosen")
        try expect(L10n.language == .en, "The choice should persist")
    }

    private static func testSettingsPaneTitles() throws {
        let previous = L10n.forcedLanguage
        defer { L10n.forcedLanguage = previous }
        let ids = SettingsWindowController.settingsTabTitles
        try expect(ids.first == "Check", "Check & Test should be the first pane")
        for id in ["Captions", "Modes", "Whiteboard"] {
            try expect(ids.contains(id), "Expected a \(id) pane")
        }
        L10n.forcedLanguage = "zh-Hant"
        for id in ids where id != "DemoType" && id != "DemoMirror" {
            let title = SettingsWindowController.displayTitle(for: id)
            try expect(title != id, "Pane \(id) should have a Chinese title")
        }
        L10n.forcedLanguage = "en"
        try expect(SettingsWindowController.displayTitle(for: "Check") == "Check & Test", "English title for Check")
        try expect(Set(ids).count == ids.count, "Pane ids must be unique")
    }

    private static func testKeystrokeDemoSequence() throws {
        let groups = KeystrokeController.demoGroups()
        let rendered = groups.map { $0.modifierGlyphs + $0.chips.map(\.text).joined() + ($0.count > 1 ? "×\($0.count)" : "") }
        try expect(rendered == ["⌘C", "⇧⌘4", "⌘Z×3"], "Demo should show ⌘C, ⇧⌘4, ⌘Z ×3, got \(rendered)")
    }

    private static func testBuildCommitFallback() throws {
        try expect(AppInfo.resolveCommit(from: nil) == "unknown", "Missing commit should read unknown")
        try expect(AppInfo.resolveCommit(from: ["TeachLensCommit": "abc1234"]) == "abc1234", "Commit should be read from Info.plist")
    }

    private static func testShortcutDescriptions() throws {
        let previous = L10n.forcedLanguage
        L10n.forcedLanguage = "zh-Hant"
        defer { L10n.forcedLanguage = previous }
        try expect(TestCenter.describe(.toggleWhiteboard) == "白板", "Shortcut names should be localized")
        try expect(TestCenter.describe(.toggleKeystrokes) == "顯示按鍵", "Shortcut names should be localized")
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
        try expect(segment == CaptionSegment(start: 10, end: 10.5, text: "今天我們"), "Pause should end the sentence, got \(String(describing: segment))")
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
