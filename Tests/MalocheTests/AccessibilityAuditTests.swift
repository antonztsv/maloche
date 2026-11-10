import AppKit
import MalocheCore
import SwiftUI
import Testing

@testable import Maloche

/// VoiceOver reads every screen sensibly, checked on the accessibility tree of views in windows never shown or key.
@MainActor @Suite struct AccessibilityAuditTests {
    private func screens() throws -> [(name: String, view: AnyView)] {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "maloche-audit-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        return try Screenshots.screens(backupRoot: root)
    }

    private func audit(_ name: String) throws -> AccessibilityAudit {
        let screen = try #require(try screens().first { $0.name == name })
        return AccessibilityAudit(screen.view)
    }

    private static func time(_ hour: Int, _ minute: Int, on day: Date) -> String {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)!.formatted(DashboardData.time)
    }

    @Test func everyScreenReadsSensibly() throws {
        for screen in try screens() {
            let audit = AccessibilityAudit(screen.view)
            #expect(audit.problems.isEmpty, "\(screen.name):\n\(audit.problems.joined(separator: "\n"))")
        }
        #expect(NSApplication.shared.keyWindow == nil)
        #expect(NSApplication.shared.windows.allSatisfy { !$0.isVisible })
    }

    @Test func theDayTimelineSpeaksItsBlocks() throws {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 9))!
        let timeline = try #require(try audit("dashboard-day").root.all.first { $0.label == "Day timeline" })
        #expect(timeline.role == "AXImage")
        for (start, end, name) in [
            ((8, 30), (10, 0), "Internal"), ((12, 15), (13, 0), "Break"), ((16, 0), (17, 0), "Acme"),
        ] {
            let span = "\(Self.time(start.0, start.1, on: day)) to \(Self.time(end.0, end.1, on: day)) \(name)"
            #expect(timeline.value.contains(span), "\(timeline.value)")
        }
    }

    @Test func theSplitBarSpeaksItsPartsAndTheDividerIsASlider() throws {
        let today = Calendar.current.startOfDay(for: .now)
        let elements = try audit("split").root.all
        let bar = try #require(elements.first { $0.role == "AXImage" })
        #expect(bar.label.contains("\(Self.time(10, 15, on: today)) to \(Self.time(10, 40, on: today)) Code Review"))
        let divider = try #require(elements.first { $0.role == "AXSlider" })
        #expect(divider.label == "Divider between Code Review and Weekly")
        #expect(divider.value == Self.time(10, 40, on: today))
    }

    @Test func theWeekBarsSpeakTheirHoursPerCustomer() throws {
        let chart = try #require(try audit("dashboard-week").root.all.first { $0.label == "Work per day" })
        #expect(chart.children.count == 7)
        let monday = try #require(chart.children.first { $0.label == "Monday" })
        #expect(monday.value == "8 hours, Acme 4 hours 30 minutes, Northwind 2 hours, Internal 1 hour 30 minutes")
        #expect(chart.children.allSatisfy { $0.role == "AXStaticText" })
    }

    @Test func theMonthGridSpeaksEveryDay() throws {
        let model = try AppModel(database: .inMemory(), stateURL: nil)
        let data = DashboardView.sample(.month, model: model).data
        let chart = try #require(try audit("dashboard-month").root.all.first { $0.label == "Work per day" })
        let days = data.summary.days.map { day in
            (
                day.interval.start.formatted(.dateTime.month(.wide).day()),
                day.work > 0 ? DurationFormat.spoken(day.work) : ""
            )
        }
        #expect(chart.children.map { [$0.label, $0.value] } == days.map { [$0.0, $0.1] })
        #expect(chart.children.allSatisfy { $0.role == "AXStaticText" })
    }

    @Test func theMoreActionsMenuNamesItself() throws {
        let menu = try #require(try audit("checkin").root.all.first { $0.role == "AXMenuButton" })
        #expect(menu.name == "More actions")
    }

    @Test func theMenuBarIconNamesEveryMode() {
        let modes: [TrackerMode] = [.tracking, .onBreak, .continuing, .off]
        let names = modes.map { MenuBarIcon.image(for: $0).accessibilityDescription ?? "" }
        #expect(names.allSatisfy { $0.hasPrefix("maloche, ") })
        #expect(Set(names).count == modes.count)
    }

    @Test func clockTimesAreTimesAndDurationsAreNot() {
        #expect(AccessibilityAudit.readsDurationAsClock("Work, 7:45"))
        #expect(AccessibilityAudit.readsDurationAsClock("Since 8:30, 2:00"))
        #expect(AccessibilityAudit.readsDurationAsClock("1:30 of logged time moves to Writing."))
        #expect(!AccessibilityAudit.readsDurationAsClock("Since 8:30, 2 hours"))
        #expect(!AccessibilityAudit.readsDurationAsClock("Workday, 8:30 to 17:00"))
        #expect(!AccessibilityAudit.readsDurationAsClock("10:15 AM to 10:40 AM Code Review"))
        #expect(!AccessibilityAudit.readsDurationAsClock("Break from 12:15 to 13:00, 45 minutes"))
    }

    @Test func symbolNamesAndFormatSpecifiersAreMeaningless() {
        #expect(AccessibilityAudit.meaningless("chevron.right"))
        #expect(AccessibilityAudit.meaningless("Create “%@”"))
        #expect(AccessibilityAudit.meaningless("…"))
        #expect(!AccessibilityAudit.meaningless("Shop 2.0"))
        #expect(!AccessibilityAudit.meaningless("More actions"))
    }
}
