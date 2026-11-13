import Foundation

public enum Updates {
    #if DEBUG
        public static let allowsLocalFeed = true
    #else
        public static let allowsLocalFeed = false
    #endif

    /// Sparkle runs only in a bundle that names a secure feed URL (https, or http on localhost in debug builds) and the key its updates are signed with.
    public static func isConfigured(info: [String: Any], allowsLocalFeed: Bool = allowsLocalFeed) -> Bool {
        func value(_ key: String) -> String? {
            (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let key = value("SUPublicEDKey"), !key.isEmpty, let feed = value("SUFeedURL") else { return false }
        guard let url = URL(string: feed), let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https"
            || (allowsLocalFeed && scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host?.lowercased()))
    }
}
