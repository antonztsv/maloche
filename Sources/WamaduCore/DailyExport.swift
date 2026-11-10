import Foundation

/// The JSON export of Daily: `activities.json` and `timesheet.json`; `group` is not read.
public struct DailyExport: Equatable, Sendable {
    public struct Activity: Decodable, Equatable, Sendable {
        public var name: String
        public var archived: Bool?
        public var lastUsed: Date?
    }

    /// Totals per activity, Daily keeps no single blocks.
    public struct Day: Decodable, Equatable, Sendable {
        public struct Entry: Decodable, Equatable, Sendable {
            public var activity: String
            public var duration: TimeInterval
        }

        public struct Info: Decodable, Equatable, Sendable {
            public var started: Date?
        }

        /// YYYY-MM-DD.
        public var date: String
        public var activities: [Entry]
        public var info: Info?
    }

    public enum File: String, Sendable {
        case activities = "activities.json"
        case timesheet = "timesheet.json"
    }

    public enum ReadError: Error, Equatable {
        case notFound
        case unreadable(File)
    }

    public var activities: [Activity]
    public var days: [Day]

    public init(activities: Data, timesheet: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            return try Date(container.decode(String.self), strategy: .iso8601)
        }
        do {
            self.activities = try decoder.decode([Activity].self, from: activities)
        } catch {
            throw ReadError.unreadable(.activities)
        }
        do {
            days = try decoder.decode([Day].self, from: timesheet)
        } catch {
            throw ReadError.unreadable(.timesheet)
        }
    }

    /// The two files themselves or the folder that holds them.
    public init(contentsOf urls: [URL]) throws {
        let candidates = urls.flatMap { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                ? [File.activities, .timesheet].map { url.appending(path: $0.rawValue) } : [url]
        }
        func find(_ file: File) throws -> Data {
            guard
                let url = candidates.first(where: {
                    $0.lastPathComponent.caseInsensitiveCompare(file.rawValue) == .orderedSame
                        && FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
                })
            else { throw ReadError.notFound }
            do {
                return try Data(contentsOf: url)
            } catch {
                throw ReadError.unreadable(file)
            }
        }
        try self.init(activities: find(.activities), timesheet: find(.timesheet))
    }
}
