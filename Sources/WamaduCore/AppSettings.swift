import Foundation

/// Everything set in the settings window, stored as one value.
public struct AppSettings: Codable, Equatable, Sendable {
    public var checkInInterval = TrackerSettings().checkInInterval
    public var awayThreshold = TrackerSettings().awayThreshold
    public var schedule = WorkSchedule.standard
    public var rounding = RoundingSettings()
    /// An action without an entry has no shortcut.
    public var shortcuts = ShortcutAction.defaultShortcuts

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
    }

    public var tracker: TrackerSettings {
        TrackerSettings(checkInInterval: checkInInterval, awayThreshold: awayThreshold, schedule: schedule)
    }

    public static let defaultsKey = "settings"

    /// The defaults when nothing is stored or the stored value is unreadable.
    public static func load(from defaults: UserDefaults) -> AppSettings {
        defaults.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) }
            ?? AppSettings()
    }

    public func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
