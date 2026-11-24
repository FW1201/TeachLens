import Foundation

/// The language TeachLens shows its interface in.
enum AppLanguage: String, CaseIterable, Sendable {
    case system, zhHant, en

    var title: String {
        switch self {
        case .system: return L10n.t("Match System", "跟隨系統")
        case .zhHant: return "繁體中文"
        case .en: return "English"
        }
    }
}

/// Two-language strings for TeachLens: Traditional Chinese or English, chosen
/// in Settings ▸ General ▸ Language (default: follow the system language).
enum L10n {
    static let defaultsKey = "appLanguage"

    /// Overrides everything; used by self-tests.
    nonisolated(unsafe) static var forcedLanguage: String?
    /// Lets self-tests use an isolated defaults suite.
    nonisolated(unsafe) static var defaults: UserDefaults = .standard

    static var language: AppLanguage {
        get { AppLanguage(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: defaultsKey) }
    }

    static var isChinese: Bool {
        if let forced = forcedLanguage { return forced.hasPrefix("zh") }
        switch language {
        case .zhHant: return true
        case .en: return false
        case .system: return (Locale.preferredLanguages.first ?? "en").hasPrefix("zh")
        }
    }

    static func t(_ english: String, _ chinese: String) -> String {
        isChinese ? chinese : english
    }

    /// Posted after the language changes so menus and windows can rebuild.
    static let didChangeNotification = Notification.Name("TeachLensLanguageDidChange")
}
