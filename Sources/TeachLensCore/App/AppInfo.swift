import Foundation

/// Product identity used across the UI (settings footer, about text).
public enum AppInfo {
    public static let productName = "TeachLens"
    public static var version: String {
        resolveVersion(from: Bundle.main.infoDictionary)
    }
    public static let copyright = "Copyright © 2026 TeachLens contributors"
    /// Open-source credits shown in Settings. TeachLens is built on ZoomIt for
    /// Mac (Microsoft, MIT) and Keyviz (Rahul Mula, GPL-3.0); see
    /// THIRD_PARTY_NOTICES.md.
    public static let attribution = "Based on ZoomIt for Mac (MIT) and Keyviz (GPL-3.0)"
    public static let license = "GPL-3.0"

    static func resolveVersion(from infoDictionary: [String: Any]?) -> String {
        for key in ["CFBundleShortVersionString", "CFBundleVersion"] {
            if let value = infoDictionary?[key] as? String, !value.isEmpty {
                return value
            }
        }
        return "Development"
    }
}
