import Foundation

/// Everything set in the settings window, stored as one value.
public struct AppSettings: Codable, Equatable, Sendable {
    public var checkInInterval = TrackerSettings().checkInInterval
    public var awayThreshold = TrackerSettings().awayThreshold
    public var schedule = WorkSchedule.standard
    public var rounding = RoundingSettings()
    /// An action without an entry has no shortcut.
    public var shortcuts = ShortcutAction.defaultShortcuts
    /// Set once the welcome window was started or closed.
    public var welcomeDone = false
    public var backup = BackupSettings()
    public var showInDock = false
    public var checkForUpdates = false

    public init() {}

    /// A missing or unreadable field keeps its default, the others are read.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? values.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        checkInInterval = value(.checkInInterval, checkInInterval)
        awayThreshold = value(.awayThreshold, awayThreshold)
        schedule = value(.schedule, schedule)
        rounding = value(.rounding, rounding)
        shortcuts = value(.shortcuts, shortcuts)
        backup = value(.backup, backup)
        showInDock = value(.showInDock, showInDock)
        checkForUpdates = value(.checkForUpdates, checkForUpdates)
        // settings stored before the welcome existed belong to someone already using the app
        welcomeDone = value(.welcomeDone, true)
    }

    public var tracker: TrackerSettings {
        TrackerSettings(checkInInterval: checkInInterval, awayThreshold: awayThreshold, schedule: schedule)
    }

    public static let defaultsKey = "settings"

    /// The defaults when nothing is stored or the stored value is unreadable.
    public static func load(from store: any SettingsStore) -> AppSettings {
        store.storedSettings().flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) } ?? AppSettings()
    }

    public func save(to store: any SettingsStore) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        store.storeSettings(data)
    }
}

/// Keeps the encoded settings value.
public protocol SettingsStore {
    /// Nil when nothing is stored.
    func storedSettings() -> Data?
    func storeSettings(_ data: Data)
}

extension UserDefaults: SettingsStore {
    public func storedSettings() -> Data? { data(forKey: AppSettings.defaultsKey) }

    public func storeSettings(_ data: Data) { set(data, forKey: AppSettings.defaultsKey) }
}

/// S14: daily backups into a folder, a fixed number of them kept.
public struct BackupSettings: Codable, Equatable, Sendable {
    public var automatic = true
    /// A chosen folder's path, nil for the Backups folder next to the database.
    public var folder: String?
    public var keep = 30

    public init(automatic: Bool = true, folder: String? = nil, keep: Int = 30) {
        self.automatic = automatic
        self.folder = folder
        self.keep = keep
    }
}
