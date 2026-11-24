import AppKit

/// Self-tests for TeachLens's teaching features beyond keystrokes.
@MainActor
enum TeachingSelfTests {
    static func run() throws {
        try testShakeDetector()
        try testSpotlightPathContainsPointer()
        try testSpotlightSettingsDecode()
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
