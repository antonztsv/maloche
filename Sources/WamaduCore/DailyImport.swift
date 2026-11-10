import Foundation

/// What importing a Daily export adds, with the customer choices of the preview. Daily keeps totals per day, so each
/// day's blocks follow one another from its start in the listed order.
public struct DailyImport: Sendable {
    /// The "x" of names like "x - y", a customer candidate.
    public struct Prefix: Equatable, Sendable, Identifiable {
        public var id: String { text.lowercased() }
        public let text: String
        /// Activities whose name starts with it.
        public let count: Int
        public var isOn: Bool
        public var customerName: String
    }

    public struct PlannedActivity: Equatable, Sendable {
        public var name: String
        public var customer: String?
        public var archived: Bool
        public var lastUsedAt: Date?
    }

    public struct PlannedBlock: Equatable, Sendable {
        public var activity: String
        public var customer: String? = nil
        public var start: Date
        public var end: Date
    }

    public struct PlannedDay: Equatable, Sendable {
        /// The local day, its blocks lie inside it.
        public var interval: DateInterval
        public var blocks: [PlannedBlock]
    }

    /// Names are matched ignoring case within their customer when written.
    public struct Plan: Equatable, Sendable {
        public var activities: [PlannedActivity]
        public var days: [PlannedDay]
    }

    private struct Imported: Sendable {
        var name: String
        var archived: Bool
        var lastUsed: Date?
    }

    public var prefixes: [Prefix]
    public var removesPrefix = true
    public let dayCount: Int
    public let firstDay: Date?
    public let lastDay: Date?
    /// Days that already have time in wamadu, they stay as they are.
    public let daysWithTime: Int
    /// Days without a start, longer than the day or listed twice.
    public let skippedDays: Int
    private let imported: [Imported]
    private let days: [PlannedDay]
    /// Break and Private by lowercased stored and shown name, no short name takes them.
    private let reserved: Set<String>

    public init(
        export: DailyExport, activities: [Activity], builtInNames: [ActivityKind: String] = [:], customers: [Customer],
        blocks: [Block], calendar: Calendar
    ) {
        var imported: [Imported] = []
        var index: [String: Int] = [:]
        @discardableResult func add(_ name: String, archived: Bool = false, lastUsed: Date? = nil) -> String? {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            if let i = index[name.lowercased()] {
                imported[i].lastUsed = Self.later(imported[i].lastUsed, lastUsed)
                return imported[i].name
            }
            index[name.lowercased()] = imported.count
            imported.append(Imported(name: name, archived: archived, lastUsed: lastUsed))
            return name
        }
        for activity in export.activities {
            add(activity.name, archived: activity.archived ?? false, lastUsed: activity.lastUsed)
        }

        var days: [PlannedDay] = []
        var dayStarts: [Date] = []
        var seen = Set<Date>()
        var dayCount = 0
        var withTime = 0
        var skipped = 0
        for day in export.days {
            let entries = day.activities.compactMap { entry in
                add(entry.activity).map { (name: $0, seconds: entry.duration.rounded()) }
            }
            .filter { $0.seconds > 0 }
            guard !entries.isEmpty else { continue }
            dayCount += 1
            guard let interval = Self.localDay(day.date, calendar) else {
                skipped += 1
                continue
            }
            dayStarts.append(interval.start)
            let total = entries.reduce(0) { $0 + $1.seconds }
            guard seen.insert(interval.start).inserted, let started = day.info?.started, total <= interval.duration
            else {
                skipped += 1
                continue
            }
            guard !blocks.contains(where: { $0.startedAt < interval.end && $0.endedAt > interval.start }) else {
                withTime += 1
                continue
            }
            var start = min(max(Self.wholeSeconds(started), interval.start), interval.end - total)
            days.append(
                PlannedDay(
                    interval: interval,
                    blocks: entries.map { entry in
                        defer { start += entry.seconds }
                        add(entry.name, lastUsed: start + entry.seconds)
                        return PlannedBlock(activity: entry.name, start: start, end: start + entry.seconds)
                    }))
        }

        let builtIns = activities.filter { $0.kind != .regular }.map(\.name) + builtInNames.values
        reserved = Set(builtIns.map { $0.lowercased() })
        var found: [String: (text: String, count: Int)] = [:]
        for name in imported.compactMap({ Self.split($0.name)?.prefix }) {
            found[name.lowercased(), default: (name, 0)].count += 1
        }
        let customers = Dictionary(customers.map { ($0.name.lowercased(), $0.name) }) { first, _ in first }
        prefixes = found.values.map { prefix in
            let customer = customers[prefix.text.lowercased()]
            return Prefix(
                text: prefix.text, count: prefix.count, isOn: prefix.count > 1 || customer != nil,
                customerName: customer ?? prefix.text.prefix(1).uppercased() + prefix.text.dropFirst())
        }
        .sorted { ($0.count, $1.text.lowercased()) > ($1.count, $0.text.lowercased()) }

        self.imported = imported
        self.days = days
        self.dayCount = dayCount
        firstDay = dayStarts.min()
        lastDay = dayStarts.max()
        daysWithTime = withTime
        skippedDays = skipped
    }

    public var activityCount: Int { imported.count }

    /// Names with a checked prefix that keep it, the short name is reserved or another of the customer's has it.
    public var keepingFullName: [String] {
        guard removesPrefix else { return [] }
        return resolved.filter { $0.customer != nil && $0.name == $0.imported.name }.map(\.name)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public var plan: Plan {
        let resolved = resolved
        let placed = Dictionary(uniqueKeysWithValues: resolved.map { ($0.imported.name, ($0.name, $0.customer)) })
        return Plan(
            activities: resolved.map {
                PlannedActivity(
                    name: $0.name, customer: $0.customer, archived: $0.imported.archived,
                    lastUsedAt: $0.imported.lastUsed)
            },
            days: days.map { day in
                var day = day
                for index in day.blocks.indices {
                    (day.blocks[index].activity, day.blocks[index].customer) = placed[day.blocks[index].activity]!
                }
                return day
            })
    }

    /// The name and customer of each imported activity after the choices.
    private var resolved: [(imported: Imported, name: String, customer: String?)] {
        let chosen = Dictionary(
            prefixes.filter(\.isOn).map { prefix in
                let name = prefix.customerName.trimmingCharacters(in: .whitespacesAndNewlines)
                return (prefix.id, name.isEmpty ? prefix.text : name)
            }
        ) { first, _ in first }
        var result = imported.map { activity in
            guard let split = Self.split(activity.name), let customer = chosen[split.prefix.lowercased()] else {
                return (imported: activity, name: activity.name, customer: String?.none)
            }
            return (
                imported: activity, name: removesPrefix ? split.rest : activity.name, customer: String?.some(customer)
            )
        }
        var changed = true
        while changed {
            changed = false
            let counts = Dictionary(
                result.map { ([$0.customer?.lowercased(), $0.name.lowercased()], 1) }, uniquingKeysWith: +)
            for index in result.indices where result[index].name != result[index].imported.name {
                let name = result[index].name.lowercased()
                if counts[[result[index].customer?.lowercased(), name], default: 0] > 1 || reserved.contains(name) {
                    result[index].name = result[index].imported.name
                    changed = true
                }
            }
        }
        return result
    }

    static func split(_ name: String) -> (prefix: String, rest: String)? {
        guard let range = name.range(of: " - ") else { return nil }
        let prefix = name[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        let rest = name[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return prefix.isEmpty || rest.isEmpty ? nil : (prefix, rest)
    }

    /// YYYY-MM-DD as a day of the calendar.
    private static func localDay(_ text: String, _ calendar: Calendar) -> DateInterval? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard components.isValidDate(in: calendar), let date = calendar.date(from: components) else { return nil }
        return calendar.dateInterval(of: .day, for: date)
    }

    private static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded())
    }

    private static func later(_ a: Date?, _ b: Date?) -> Date? {
        [a, b].compactMap { $0 }.max()
    }
}
