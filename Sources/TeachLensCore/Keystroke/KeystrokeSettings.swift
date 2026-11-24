import Foundation

/// Where the keystroke HUD sits on the screen.
enum KeystrokePosition: String, Codable, CaseIterable, Sendable {
    case bottomLeft, bottomCenter, bottomRight, topLeft, topCenter, topRight

    var title: String {
        switch self {
        case .bottomLeft: return L10n.t("Bottom Left", "左下")
        case .bottomCenter: return L10n.t("Bottom Center", "中下")
        case .bottomRight: return L10n.t("Bottom Right", "右下")
        case .topLeft: return L10n.t("Top Left", "左上")
        case .topCenter: return L10n.t("Top Center", "中上")
        case .topRight: return L10n.t("Top Right", "右上")
        }
    }

    var isTop: Bool { self == .topLeft || self == .topCenter || self == .topRight }
}

/// Which system's shortcut the main pill shows. The other one, when
/// "Windows 對照" is on, appears as a smaller line under it.
enum KeystrokePlatform: String, Codable, CaseIterable, Sendable {
    case mac, windows

    var title: String {
        switch self {
        case .mac: return L10n.t("Mac first, Windows below", "Mac 為主、Windows 為輔")
        case .windows: return L10n.t("Windows first, Mac below", "Windows 為主、Mac 為輔")
        }
    }

    var shortTitle: String {
        switch self {
        case .mac: return "Mac"
        case .windows: return "Windows"
        }
    }
}

/// How the pill's background is drawn.
enum KeystrokeGlass: String, Codable, CaseIterable, Sendable {
    /// Liquid Glass on macOS 26 and later, frosted material before that.
    case automatic
    /// Frosted material on every macOS version.
    case frosted
    /// An opaque dark pill, the most legible over busy video.
    case solid

    var title: String {
        switch self {
        case .automatic: return L10n.t("Liquid Glass (macOS 26+)", "Liquid Glass（macOS 26 以上）")
        case .frosted: return L10n.t("Frosted", "霧面")
        case .solid: return L10n.t("Solid", "實色")
        }
    }
}

/// Persisted keystroke-visualization preferences. Decoding tolerates missing
/// keys so new fields can be added without resetting a user's choices.
struct KeystrokeSettings: Codable, Equatable, Sendable {
    var enabled = true
    var filter: KeystrokeFilter = .modifiers
    var allowedKeys: [String] = [KeyName.controlLeft, KeyName.metaLeft, KeyName.alt]
    var showHistory = false
    var maxHistory = 3
    var showMouseEvents = true
    var showClickRipples = true
    var lingerSeconds: Double = 3
    var dragThreshold: Double = 50
    var position: KeystrokePosition = .bottomCenter
    var glass: KeystrokeGlass = .automatic
    /// Multiplies every size in the HUD.
    var scale: Double = 1.0
    /// Distance from the screen edge, in points.
    var margin: Double = 64
    /// Show the Windows equivalent under each combination ("Windows 對照").
    var windowsEquivalent = false
    /// Show the Windows shortcut in the main pill and the Mac one below it.
    var primaryPlatform: KeystrokePlatform = .mac
    /// Global toggle hotkey: virtual key code and NSEvent modifier raw value.
    /// Defaults to Control+0 (ZoomIt uses Control+1 … Control+9).
    var toggleKeyCode = 29
    var toggleModifiers: UInt = 1 << 18

    init() {}

    var engineConfig: KeystrokeEngineConfig {
        KeystrokeEngineConfig(
            filter: filter,
            allowedKeys: allowedKeys,
            showHistory: showHistory,
            maxHistory: max(1, maxHistory),
            showMouseEvents: showMouseEvents,
            lingerDuration: max(0.5, lingerSeconds),
            dragThreshold: dragThreshold
        )
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, filter, allowedKeys, showHistory, maxHistory, showMouseEvents, showClickRipples
        case lingerSeconds, dragThreshold, position, glass, scale, margin, toggleKeyCode, toggleModifiers
        case windowsEquivalent, primaryPlatform
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = KeystrokeSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        filter = (try? c.decodeIfPresent(KeystrokeFilter.self, forKey: .filter)) ?? d.filter
        allowedKeys = try c.decodeIfPresent([String].self, forKey: .allowedKeys) ?? d.allowedKeys
        showHistory = try c.decodeIfPresent(Bool.self, forKey: .showHistory) ?? d.showHistory
        maxHistory = try c.decodeIfPresent(Int.self, forKey: .maxHistory) ?? d.maxHistory
        showMouseEvents = try c.decodeIfPresent(Bool.self, forKey: .showMouseEvents) ?? d.showMouseEvents
        showClickRipples = try c.decodeIfPresent(Bool.self, forKey: .showClickRipples) ?? d.showClickRipples
        lingerSeconds = try c.decodeIfPresent(Double.self, forKey: .lingerSeconds) ?? d.lingerSeconds
        dragThreshold = try c.decodeIfPresent(Double.self, forKey: .dragThreshold) ?? d.dragThreshold
        position = (try? c.decodeIfPresent(KeystrokePosition.self, forKey: .position)) ?? d.position
        glass = (try? c.decodeIfPresent(KeystrokeGlass.self, forKey: .glass)) ?? d.glass
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? d.scale
        margin = try c.decodeIfPresent(Double.self, forKey: .margin) ?? d.margin
        windowsEquivalent = try c.decodeIfPresent(Bool.self, forKey: .windowsEquivalent) ?? d.windowsEquivalent
        primaryPlatform = (try? c.decodeIfPresent(KeystrokePlatform.self, forKey: .primaryPlatform)) ?? d.primaryPlatform
        toggleKeyCode = try c.decodeIfPresent(Int.self, forKey: .toggleKeyCode) ?? d.toggleKeyCode
        toggleModifiers = try c.decodeIfPresent(UInt.self, forKey: .toggleModifiers) ?? d.toggleModifiers
    }
}

/// Stores `KeystrokeSettings` as one JSON blob in UserDefaults.
struct KeystrokeSettingsStore {
    static let defaultsKey = "keystrokeSettings"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> KeystrokeSettings {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let settings = try? JSONDecoder().decode(KeystrokeSettings.self, from: data) else {
            return KeystrokeSettings()
        }
        return settings
    }

    func save(_ settings: KeystrokeSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
