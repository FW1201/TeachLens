import Foundation

/// Minimal two-language strings for TeachLens's own UI: Traditional Chinese
/// when the user's preferred language is Chinese, English otherwise.
/// (The inherited ZoomIt screens remain English.)
enum L10n {
    nonisolated(unsafe) static var forcedLanguage: String?

    static var isChinese: Bool {
        let language = forcedLanguage ?? Locale.preferredLanguages.first ?? "en"
        return language.hasPrefix("zh")
    }

    static func t(_ english: String, _ chinese: String) -> String {
        isChinese ? chinese : english
    }
}
