import AppKit
import SwiftUI
import WamaduCore

extension AppModel {
    /// One setting, a change applies and is stored right away.
    func setting<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding {
            self.settings[keyPath: keyPath]
        } set: { value in
            var settings = self.settings
            settings[keyPath: keyPath] = value
            self.update(settings)
        }
    }
}

/// "15 minutes", "1 hour".
private func durationName(_ seconds: TimeInterval) -> String {
    Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .wide))
}

/// Check-in interval, away threshold, open at login and the global shortcuts.
struct GeneralSettingsView: View {
    let model: AppModel
    var isLoginItem: () -> Bool = { LoginItem.isEnabled }
    var onRecording: (Bool) -> Void = { _ in }
    @State private var openAtLogin = false

    private static let steps: [TimeInterval] = [5, 10, 15, 20, 30, 45, 60].map { $0 * 60 }

    var body: some View {
        Form {
            Section {
                Picker(selection: model.setting(\.checkInInterval)) {
                    durations(including: model.settings.checkInInterval)
                } label: {
                    Text("Check in every")
                    Text("wamadu asks what you are working on.")
                }
                Picker(selection: model.setting(\.awayThreshold)) {
                    durations(including: model.settings.awayThreshold)
                } label: {
                    Text("Away after")
                    Text("When you come back, wamadu asks what you did.")
                }
                Toggle("Open at login", isOn: Binding(get: { openAtLogin }, set: setOpenAtLogin))
            }
            ShortcutsSection(model: model, onRecording: onRecording)
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: SettingsWindowController.width)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { openAtLogin = isLoginItem() }
    }

    /// A value set elsewhere stays selectable.
    private func durations(including value: TimeInterval) -> some View {
        ForEach(Set(Self.steps + [value]).sorted(), id: \.self) { seconds in
            Text(durationName(seconds)).tag(seconds)
        }
    }

    private func setOpenAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
        } catch {
            appLog.error("changing the login item failed: \(String(describing: error), privacy: .public)")
            NSSound.beep()
        }
        openAtLogin = isLoginItem()
    }
}

/// Per weekday on or off, from and to; a day switched on takes the times of the first planned day.
struct ScheduleSettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            Section {
                ForEach(weekdays, id: \.self, content: row)
            } footer: {
                Text("wamadu only checks in during these hours. You can always start tracking from the menu bar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: SettingsWindowController.width)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// From the calendar's first weekday on, 1 is Sunday.
    private var weekdays: [Int] {
        (0..<7).map { (model.calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    private var template: WorkSchedule.Plan {
        weekdays.lazy.compactMap { model.settings.schedule.plans[$0] }.first ?? .init(start: 8 * 60, end: 18 * 60)
    }

    private func row(_ weekday: Int) -> some View {
        let name = model.calendar.standaloneWeekdaySymbols[weekday - 1]
        let plan = model.settings.schedule.plans[weekday]
        let shown = plan ?? template
        return HStack(spacing: 8) {
            Text(name)
                .frame(width: 96, alignment: .leading)
            Group {
                DatePicker(
                    String(localized: "Start on \(name)"), selection: time(weekday, \.start),
                    in: date(0)...date(max(shown.end - 1, 0)), displayedComponents: .hourAndMinute)
                Text("to")
                    .foregroundStyle(.secondary)
                DatePicker(
                    String(localized: "End on \(name)"), selection: time(weekday, \.end),
                    in: date(min(shown.start + 1, Self.lastMinute))...date(Self.lastMinute),
                    displayedComponents: .hourAndMinute)
            }
            .disabled(plan == nil)
            Spacer()
            Toggle(name, isOn: Binding(get: { plan != nil }, set: { set(weekday, $0 ? template : nil) }))
                .toggleStyle(.switch)
        }
        .datePickerStyle(.field)
        .labelsHidden()
    }

    private static let lastMinute = 24 * 60 - 1

    private func time(_ weekday: Int, _ keyPath: WritableKeyPath<WorkSchedule.Plan, Int>) -> Binding<Date> {
        Binding {
            date((model.settings.schedule.plans[weekday] ?? template)[keyPath: keyPath])
        } set: { value in
            guard var plan = model.settings.schedule.plans[weekday] else { return }
            let parts = model.calendar.dateComponents([.hour, .minute], from: value)
            plan[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            set(weekday, plan)
        }
    }

    private func set(_ weekday: Int, _ plan: WorkSchedule.Plan?) {
        var settings = model.settings
        settings.schedule.plans[weekday] = plan
        model.update(settings)
    }

    /// The minutes after midnight on a day without a DST change.
    private func date(_ minutes: Int) -> Date {
        let day = model.calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        return model.calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)!
    }
}

/// Step, mode and level of the rounding of shown durations.
struct RoundingSettingsView: View {
    let model: AppModel

    var body: some View {
        let rounds = (model.settings.rounding.stepMinutes ?? 0) > 0
        Form {
            Section {
                Picker("Round to", selection: model.setting(\.rounding.stepMinutes)) {
                    Text("No rounding").tag(Int?.none)
                    ForEach([5, 6, 10, 15, 30, 60], id: \.self) { minutes in
                        Text(durationName(TimeInterval(minutes * 60))).tag(Int?.some(minutes))
                    }
                }
                Picker("Rounding", selection: model.setting(\.rounding.mode)) {
                    Text("To nearest").tag(RoundingSettings.Mode.nearest)
                    Text("Always up").tag(RoundingSettings.Mode.up)
                }
                .disabled(!rounds)
                Picker("Apply to", selection: model.setting(\.rounding.level)) {
                    Text("Each entry").tag(RoundingSettings.Level.entry)
                    Text("Each day per activity").tag(RoundingSettings.Level.dayAndActivity)
                    Text("Each week or month per activity").tag(RoundingSettings.Level.period)
                }
                .disabled(!rounds)
            } footer: {
                Text("Rounding only changes how times are shown and exported. Your recorded times stay exact.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: SettingsWindowController.width)
        .fixedSize(horizontal: false, vertical: true)
    }
}
