import AppKit
import QuartzCore

/// Persisted spotlight and cursor-highlight preferences.
struct SpotlightSettings: Codable, Equatable, Sendable {
    /// Radius of the lit area around the pointer, in points.
    var radius: Double = 150
    /// Opacity of the dimmed area (0…0.9).
    var dimming: Double = 0.6
    /// Lit area shape: circle, or a wide rounded rectangle for lines of text.
    var shape: SpotlightShape = .circle
    /// A coloured ring that follows the pointer.
    var highlightEnabled = false
    var highlightDiameter: Double = 56
    var highlightColor: HighlightColor = .yellow
    /// Shaking the mouse briefly shows a large ring around the pointer.
    var shakeToFind = true
    /// Global toggle hotkey for the spotlight (default Control+Shift+0).
    var toggleKeyCode = 29
    var toggleModifiers: UInt = (1 << 18) | (1 << 17)

    init() {}

    private enum CodingKeys: String, CodingKey {
        case radius, dimming, shape, highlightEnabled, highlightDiameter, highlightColor, shakeToFind
        case toggleKeyCode, toggleModifiers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SpotlightSettings()
        radius = try c.decodeIfPresent(Double.self, forKey: .radius) ?? d.radius
        dimming = try c.decodeIfPresent(Double.self, forKey: .dimming) ?? d.dimming
        shape = (try? c.decodeIfPresent(SpotlightShape.self, forKey: .shape)) ?? d.shape
        highlightEnabled = try c.decodeIfPresent(Bool.self, forKey: .highlightEnabled) ?? d.highlightEnabled
        highlightDiameter = try c.decodeIfPresent(Double.self, forKey: .highlightDiameter) ?? d.highlightDiameter
        highlightColor = (try? c.decodeIfPresent(HighlightColor.self, forKey: .highlightColor)) ?? d.highlightColor
        shakeToFind = try c.decodeIfPresent(Bool.self, forKey: .shakeToFind) ?? d.shakeToFind
        toggleKeyCode = try c.decodeIfPresent(Int.self, forKey: .toggleKeyCode) ?? d.toggleKeyCode
        toggleModifiers = try c.decodeIfPresent(UInt.self, forKey: .toggleModifiers) ?? d.toggleModifiers
    }

    static let radiusRange: ClosedRange<Double> = 60...500
    static let dimmingRange: ClosedRange<Double> = 0.2...0.9
}

enum SpotlightShape: String, Codable, CaseIterable, Sendable {
    case circle, bar

    var title: String { self == .circle ? "Circle" : "Wide Bar" }
}

enum HighlightColor: String, Codable, CaseIterable, Sendable {
    case yellow, cyan, pink, green

    var title: String { rawValue.capitalized }

    var nsColor: NSColor {
        switch self {
        case .yellow: return NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.0, alpha: 1)
        case .cyan: return NSColor(calibratedRed: 0.0, green: 0.83, blue: 1.0, alpha: 1)
        case .pink: return NSColor(calibratedRed: 1.0, green: 0.3, blue: 0.62, alpha: 1)
        case .green: return NSColor(calibratedRed: 0.2, green: 0.9, blue: 0.45, alpha: 1)
        }
    }
}

struct SpotlightSettingsStore {
    static let defaultsKey = "spotlightSettings"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> SpotlightSettings {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let settings = try? JSONDecoder().decode(SpotlightSettings.self, from: data) else {
            return SpotlightSettings()
        }
        return settings
    }

    func save(_ settings: SpotlightSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}

/// Detects a "shake" gesture: several quick horizontal direction reversals.
struct ShakeDetector: Sendable {
    var window: TimeInterval = 0.6
    var requiredReversals = 4
    var minimumSegment: Double = 30

    private var lastX: Double?
    private var direction = 0
    private var segmentStartX: Double = 0
    private var reversals: [TimeInterval] = []
    private var lastTrigger: TimeInterval = -10

    /// Feeds a pointer sample; returns true when a shake is recognised.
    mutating func add(x: Double, at time: TimeInterval) -> Bool {
        defer { lastX = x }
        guard let lastX else {
            segmentStartX = x
            return false
        }
        let dx = x - lastX
        guard abs(dx) > 0.5 else { return false }
        let newDirection = dx > 0 ? 1 : -1
        if newDirection != direction {
            if direction != 0 && abs(lastX - segmentStartX) >= minimumSegment {
                reversals.append(time)
            }
            direction = newDirection
            segmentStartX = lastX
        }
        reversals.removeAll { time - $0 > window }
        if reversals.count >= requiredReversals && time - lastTrigger > 1.0 {
            reversals.removeAll()
            lastTrigger = time
            return true
        }
        return false
    }
}

/// Dims the screen except around the pointer, draws an optional cursor ring
/// and a "find my cursor" pulse. Click-through; follows the pointer's screen.
@MainActor
final class SpotlightController: NSObject, NSMenuItemValidation {
    private let store: SpotlightSettingsStore
    private(set) var settings: SpotlightSettings
    private(set) var spotlightOn = false

    private var panel: NSPanel?
    private let dimLayer = CAShapeLayer()
    private let rimLayer = CAShapeLayer()
    private let haloLayer = CAShapeLayer()
    private let pulseLayer = CAShapeLayer()
    private var timer: Timer?
    private var lastPoint: NSPoint = .zero
    private var shake = ShakeDetector()

    var onHotkeyChange: (() -> Void)?

    init(store: SpotlightSettingsStore = SpotlightSettingsStore()) {
        self.store = store
        self.settings = store.load()
        super.init()
    }

    func start() {
        refreshRunningState()
    }

    var windowNumberForCaptureExclusion: Int? {
        guard let panel, panel.isVisible else { return nil }
        return panel.windowNumber
    }

    @objc func toggleSpotlight() {
        setSpotlight(!spotlightOn)
    }

    func setSpotlight(_ on: Bool) {
        spotlightOn = on
        refreshRunningState()
    }

    @objc func toggleHighlight() {
        update { $0.highlightEnabled.toggle() }
    }

    func update(_ change: (inout SpotlightSettings) -> Void) {
        let old = settings
        change(&settings)
        settings.radius = min(max(settings.radius, SpotlightSettings.radiusRange.lowerBound), SpotlightSettings.radiusRange.upperBound)
        settings.dimming = min(max(settings.dimming, SpotlightSettings.dimmingRange.lowerBound), SpotlightSettings.dimmingRange.upperBound)
        guard settings != old else { return }
        store.save(settings)
        refreshRunningState()
        if old.toggleKeyCode != settings.toggleKeyCode || old.toggleModifiers != settings.toggleModifiers {
            onHotkeyChange?()
        }
    }

    // MARK: Running state

    private var needsPanel: Bool {
        spotlightOn || settings.highlightEnabled || settings.shakeToFind
    }

    private func refreshRunningState() {
        if needsPanel {
            ensurePanel()
            startTimer()
            applyStyle()
            updateLayers(force: true)
        } else {
            timer?.invalidate()
            timer = nil
            panel?.orderOut(nil)
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateLayers(force: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = NSPanel(
            contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600),
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
        // Below the zoom/draw overlay (screenSaver) so annotations stay bright,
        // above ordinary windows.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none

        let view = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        view.wantsLayer = true
        view.autoresizingMask = [.width, .height]
        let root = CALayer()
        view.layer = root
        for layer in [dimLayer, rimLayer, haloLayer, pulseLayer] {
            layer.actions = ["path": NSNull(), "position": NSNull(), "bounds": NSNull(), "opacity": NSNull(), "transform": NSNull()]
            root.addSublayer(layer)
        }
        dimLayer.fillRule = .evenOdd
        rimLayer.fillColor = NSColor.clear.cgColor
        haloLayer.lineWidth = 3
        pulseLayer.fillColor = NSColor.clear.cgColor
        pulseLayer.lineWidth = 6
        pulseLayer.opacity = 0
        panel.contentView = view
        self.panel = panel
        panel.orderFrontRegardless()
    }

    private func applyStyle() {
        dimLayer.fillColor = NSColor.black.withAlphaComponent(settings.dimming).cgColor
        rimLayer.strokeColor = NSColor.white.withAlphaComponent(0.35).cgColor
        rimLayer.lineWidth = 2
        let color = settings.highlightColor.nsColor
        haloLayer.strokeColor = color.withAlphaComponent(0.95).cgColor
        haloLayer.fillColor = color.withAlphaComponent(0.22).cgColor
        pulseLayer.strokeColor = color.cgColor
    }

    private func updateLayers(force: Bool) {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime
        if settings.shakeToFind, shake.add(x: Double(mouse.x), at: now) {
            runPulse()
        }
        guard force || mouse != lastPoint else { return }
        lastPoint = mouse

        if !panel.frame.contains(mouse),
           let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            panel.setFrame(screen.frame, display: false)
        }
        if !panel.isVisible { panel.orderFrontRegardless() }

        let bounds = CGRect(origin: .zero, size: panel.frame.size)
        let p = CGPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if spotlightOn {
            let hole = Self.spotlightPath(center: p, radius: settings.radius, shape: settings.shape)
            let path = CGMutablePath()
            path.addRect(bounds)
            path.addPath(hole)
            dimLayer.path = path
            rimLayer.path = hole
            dimLayer.isHidden = false
            rimLayer.isHidden = false
        } else {
            dimLayer.isHidden = true
            rimLayer.isHidden = true
        }
        if settings.highlightEnabled {
            let r = settings.highlightDiameter / 2
            haloLayer.path = CGPath(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2), transform: nil)
            haloLayer.isHidden = false
        } else {
            haloLayer.isHidden = true
        }
        pulseLayer.position = p
        CATransaction.commit()
    }

    static func spotlightPath(center: CGPoint, radius: Double, shape: SpotlightShape) -> CGPath {
        switch shape {
        case .circle:
            return CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2), transform: nil)
        case .bar:
            let width = radius * 4
            let height = radius * 0.9
            let rect = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
            return CGPath(roundedRect: rect, cornerWidth: height / 2, cornerHeight: height / 2, transform: nil)
        }
    }

    private func runPulse() {
        let r: CGFloat = 70
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pulseLayer.bounds = CGRect(x: 0, y: 0, width: r * 2, height: r * 2)
        pulseLayer.path = CGPath(ellipseIn: pulseLayer.bounds, transform: nil)
        CATransaction.commit()

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 3.0
        scale.toValue = 0.6
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.15, 0.7, 1]
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.9
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        pulseLayer.add(group, forKey: "pulse")
    }

    // MARK: Menu

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Spotlight")
        func add(_ title: String, _ action: Selector, _ represented: String? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = represented
            menu.addItem(item)
        }
        add("Cursor Highlight", #selector(toggleHighlight))
        add("Shake to Find Cursor", #selector(toggleShake))
        menu.addItem(.separator())
        for shape in SpotlightShape.allCases {
            add(shape.title, #selector(setShape(_:)), shape.rawValue)
        }
        add("Larger Spotlight", #selector(largerSpotlight))
        add("Smaller Spotlight", #selector(smallerSpotlight))
        add("Darker", #selector(darker))
        add("Lighter", #selector(lighter))
        menu.addItem(.separator())
        for color in HighlightColor.allCases {
            add(color.title, #selector(setColor(_:)), color.rawValue)
        }
        return menu
    }

    @objc private func toggleShake() { update { $0.shakeToFind.toggle() } }
    @objc private func largerSpotlight() { update { $0.radius += 30 } }
    @objc private func smallerSpotlight() { update { $0.radius -= 30 } }
    @objc private func darker() { update { $0.dimming += 0.1 } }
    @objc private func lighter() { update { $0.dimming -= 0.1 } }

    @objc private func setShape(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let shape = SpotlightShape(rawValue: raw) else { return }
        update { $0.shape = shape }
    }

    @objc private func setColor(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let color = HighlightColor(rawValue: raw) else { return }
        update { $0.highlightColor = color }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let raw = menuItem.representedObject as? String
        switch menuItem.action {
        case #selector(toggleSpotlight):
            menuItem.state = spotlightOn ? .on : .off
        case #selector(toggleHighlight):
            menuItem.state = settings.highlightEnabled ? .on : .off
        case #selector(toggleShake):
            menuItem.state = settings.shakeToFind ? .on : .off
        case #selector(setShape(_:)):
            menuItem.state = raw == settings.shape.rawValue ? .on : .off
        case #selector(setColor(_:)):
            menuItem.state = raw == settings.highlightColor.rawValue ? .on : .off
        case #selector(largerSpotlight):
            return settings.radius < SpotlightSettings.radiusRange.upperBound
        case #selector(smallerSpotlight):
            return settings.radius > SpotlightSettings.radiusRange.lowerBound
        case #selector(darker):
            return settings.dimming < SpotlightSettings.dimmingRange.upperBound
        case #selector(lighter):
            return settings.dimming > SpotlightSettings.dimmingRange.lowerBound
        default:
            break
        }
        return true
    }
}
