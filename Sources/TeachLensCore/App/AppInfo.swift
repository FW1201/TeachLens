import Foundation

/// Product identity used across the UI (settings footer, about text).
public enum AppInfo {
    public static let productName = "TeachLens"
    public static var version: String {
        resolveVersion(from: Bundle.main.infoDictionary)
    }
    /// Short git commit the app was built from (Info.plist `TeachLensCommit`).
    public static var commit: String {
        resolveCommit(from: Bundle.main.infoDictionary)
    }
    public static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "unbundled"
    }
    /// The ad-hoc contributor build uses a `.dev` bundle id and its own permissions.
    public static var isDevBuild: Bool {
        bundleIdentifier.hasSuffix(".dev") || Bundle.main.bundleIdentifier == nil
    }

    static func resolveCommit(from infoDictionary: [String: Any]?) -> String {
        if let value = infoDictionary?["TeachLensCommit"] as? String, !value.isEmpty {
            return value
        }
        return "unknown"
    }
    public static let copyright = "Copyright © 2026 TeachLens contributors"
    /// Open-source credits shown in Settings. TeachLens is built on ZoomIt for
    /// Mac (Microsoft, MIT) and Keyviz (Rahul Mula, GPL-3.0); see
    /// THIRD_PARTY_NOTICES.md.
    public static let attribution = "Based on ZoomIt for Mac (MIT) and Keyviz (GPL-3.0)"
    /// Fork maintainer credit (Journal of Digital Narrative / 數位敘事力期刊).
    public static let forkCredit = "Fork 開發：數位敘事力期刊"
    public static let forkURL = "https://www.facebook.com/Journal.of.Digital.Narrative"
    public static let repositoryURL = "https://github.com/FW1201/TeachLens"

    static func resolveVersion(from infoDictionary: [String: Any]?) -> String {
        // The full label, including a pre-release tag such as "1.3.0-beta.1".
        for key in ["TeachLensDisplayVersion", "CFBundleShortVersionString", "CFBundleVersion"] {
            if let value = infoDictionary?[key] as? String, !value.isEmpty {
                return value
            }
        }
        return "Development"
    }
}
