import Foundation

public enum Updates {
    /// Sparkle runs only in a bundle that names an absolute feed URL and the key its updates are signed with.
    public static func isConfigured(info: [String: Any]) -> Bool {
        func value(_ key: String) -> String? {
            (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let key = value("SUPublicEDKey"), !key.isEmpty, let feed = value("SUFeedURL") else { return false }
        return URL(string: feed)?.scheme != nil
    }
}
