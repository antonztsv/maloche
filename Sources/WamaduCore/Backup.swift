import Foundation
import GRDB

/// S14: a backup file, named by its local time so that name order is time order.
public struct Backup: Equatable, Sendable {
    public let url: URL
    public let date: Date

    /// "wamadu 2026-11-10 09.00.sqlite"
    static func fileName(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "wamadu %04d-%02d-%02d %02d.%02d.sqlite", parts.year!, parts.month!, parts.day!, parts.hour!,
            parts.minute!)
    }

    static func date(fromFileName name: String, calendar: Calendar) -> Date? {
        guard let match = name.wholeMatch(of: /wamadu (\d{4})-(\d{2})-(\d{2}) (\d{2})\.(\d{2})\.sqlite/) else {
            return nil
        }
        return calendar.date(
            from: DateComponents(
                year: Int(match.1), month: Int(match.2), day: Int(match.3), hour: Int(match.4), minute: Int(match.5)))
    }

    /// The backups in the folder, oldest first; other files are left out.
    public static func all(in folder: URL, calendar: Calendar) -> [Backup] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let backups = urls.compactMap { url in
            date(fromFileName: url.lastPathComponent, calendar: calendar).map { Backup(url: url, date: $0) }
        }
        return backups.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }
}

/// A backup read into memory, checked and migrated; nothing is written before it is restored.
public struct RestorableBackup: Sendable {
    public let date: Date
    let content: DatabaseQueue
}

extension AppDatabase {
    /// Writes a consistent copy into the folder, then deletes the oldest backups beyond `keep` among those dated up to
    /// the new one, never the new one.
    @discardableResult
    public func backUp(to folder: URL, at date: Date, keep: Int, calendar: Calendar) throws -> Backup {
        let files = FileManager.default
        // only the last folder is created, a chosen folder on a volume that is not mounted stays absent
        if !files.fileExists(atPath: folder.path(percentEncoded: false)) {
            try files.createDirectory(at: folder, withIntermediateDirectories: false)
        }
        let url = folder.appending(path: Backup.fileName(for: date, calendar: calendar))
        // a copy that fails halfway never carries a backup name
        let partial = folder.appending(path: ".wamadu-\(UUID().uuidString).partial")
        defer { try? files.removeItem(at: partial) }
        let copy = try DatabaseQueue(path: partial.path(percentEncoded: false))
        try dbQueue.backup(to: copy)
        try copy.close()
        if files.fileExists(atPath: url.path(percentEncoded: false)) { try files.removeItem(at: url) }
        try files.moveItem(at: partial, to: url)
        // backups dated after this one, e.g. while the clock was ahead, are left alone
        let older = Backup.all(in: folder, calendar: calendar).filter {
            $0.url.lastPathComponent != url.lastPathComponent && $0.date <= date
        }
        for old in older.dropLast(max(keep - 1, 0)) {
            // one that cannot be deleted now goes with the next backup
            try? files.removeItem(at: old.url)
        }
        return Backup(url: url, date: date)
    }

    /// The file's content if it is a wamadu database, migrated to the current version; the file is only read.
    public static func readBackup(at url: URL, calendar: Calendar) throws -> RestorableBackup {
        try readBackup(at: url, calendar: calendar, migrator: migrator)
    }

    static func readBackup(at url: URL, calendar: Calendar, migrator: DatabaseMigrator) throws -> RestorableBackup {
        let content = try DatabaseQueue()
        do {
            var configuration = Configuration()
            configuration.readonly = true
            let file = try DatabaseQueue(path: url.path(percentEncoded: false), configuration: configuration)
            try file.read { db in
                let applied = try migrator.appliedIdentifiers(db)
                guard !applied.isEmpty, applied.isSubset(of: migrator.migrations),
                    try ["customer", "project", "activity", "block"].allSatisfy({ try db.tableExists($0) }),
                    try String.fetchOne(db, sql: "PRAGMA quick_check") == "ok"
                else { throw WamaduError.notABackup }
            }
            try file.backup(to: content)
            try file.close()
        } catch {
            throw WamaduError.notABackup
        }
        try migrator.migrate(content)
        let date =
            try Backup.date(fromFileName: url.lastPathComponent, calendar: calendar)
            ?? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
        return RestorableBackup(date: date, content: content)
    }

    /// Writes the backup over the content in one step, the connection stays open.
    public func restore(_ backup: RestorableBackup) throws {
        try backup.content.backup(to: dbQueue)
    }
}
