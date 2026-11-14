import AppKit
import MalocheCore
import SwiftUI

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
                    Self.durations(including: model.settings.checkInInterval)
                } label: {
                    Text("Check in every")
                    Text("maloche asks what you are working on.")
                }
                Picker(selection: model.setting(\.awayThreshold)) {
                    Self.durations(including: model.settings.awayThreshold)
                } label: {
                    Text("Away after")
                    Text("When you come back, maloche asks what you did.")
                }
                Toggle("Open at login", isOn: Binding(get: { openAtLogin }, set: setOpenAtLogin))
                Toggle("Show in Dock", isOn: model.setting(\.showInDock))
            }
            ShortcutsSection(model: model, onRecording: onRecording)
        }
        .settingsPane()
        .onAppear { openAtLogin = isLoginItem() }
    }

    /// A value set elsewhere stays selectable.
    static func durations(including value: TimeInterval) -> some View {
        ForEach(Set(Self.steps + [value]).sorted(), id: \.self) { seconds in
            Text(durationName(seconds)).tag(seconds)
        }
    }

    private func setOpenAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
        } catch {
            appLog.error("changing the login item failed: \(String(describing: error), privacy: .private)")
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
                ForEach(model.calendar.orderedWeekdays, id: \.self, content: row)
            } footer: {
                Text("maloche only checks in during these hours. You can always start tracking from the menu bar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .settingsPane()
    }

    private var template: WorkSchedule.Plan {
        model.settings.schedule.firstPlan(calendar: model.calendar)
    }

    private func row(_ weekday: Int) -> some View {
        let name = model.calendar.standaloneWeekdaySymbols[weekday - 1]
        let plan = model.settings.schedule.plans[weekday]
        return HStack(spacing: 8) {
            Text(name)
                .frame(width: 96, alignment: .leading)
            PlanFields(
                plan: Binding {
                    plan ?? template
                } set: {
                    if plan != nil { set(weekday, $0) }
                },
                startLabel: String(localized: "Start on \(name)"), endLabel: String(localized: "End on \(name)"),
                calendar: model.calendar
            )
            .disabled(plan == nil)
            Spacer()
            Toggle(name, isOn: Binding(get: { plan != nil }, set: { set(weekday, $0 ? template : nil) }))
                .toggleStyle(.switch)
        }
        .datePickerStyle(.field)
        .labelsHidden()
    }

    private func set(_ weekday: Int, _ plan: WorkSchedule.Plan?) {
        var settings = model.settings
        settings.schedule.plans[weekday] = plan
        model.update(settings)
    }
}

/// Start and end of a plan as two time fields with "to" between, the end stays after the start.
struct PlanFields: View {
    @Binding var plan: WorkSchedule.Plan
    let startLabel: String
    let endLabel: String
    let calendar: Calendar

    var body: some View {
        DatePicker(
            startLabel, selection: time(\.start), in: date(0)...date(max(plan.end - 1, 0)),
            displayedComponents: .hourAndMinute)
        Text("to")
            .foregroundStyle(.secondary)
        DatePicker(
            endLabel, selection: time(\.end), in: date(min(plan.start + 1, Self.lastMinute))...date(Self.lastMinute),
            displayedComponents: .hourAndMinute)
    }

    private static let lastMinute = 24 * 60 - 1

    private func time(_ keyPath: WritableKeyPath<WorkSchedule.Plan, Int>) -> Binding<Date> {
        Binding {
            date(plan[keyPath: keyPath])
        } set: { value in
            let parts = calendar.dateComponents([.hour, .minute], from: value)
            plan[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }

    /// The minutes after midnight on a day without a DST change.
    private func date(_ minutes: Int) -> Date {
        let day = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)!
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
        .settingsPane()
    }
}

/// Automatic backups into a folder, restoring one, and the import from Daily.
struct BackupSettingsView: View {
    let model: AppModel
    @State private var importFlow = DailyImportFlow()
    @State private var restoreFlow = RestoreFlow()

    private static let keepChoices = [7, 14, 30, 60, 90]

    var body: some View {
        let folder = model.backupFolder?.path(percentEncoded: false) ?? ""
        Form {
            Section {
                Toggle("Back up automatically", isOn: model.setting(\.backup.automatic))
                LabeledContent {
                    Button("Choose…", action: chooseFolder)
                } label: {
                    Text("Folder")
                    Text(verbatim: Self.folderName(folder))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .help(folder)
                Picker("Keep", selection: model.setting(\.backup.keep)) {
                    ForEach(Set(Self.keepChoices + [model.settings.backup.keep]).sorted(), id: \.self) { count in
                        Text("^[\(count) backup](inflect: true)").tag(count)
                    }
                }
                LabeledContent {
                    HStack(spacing: 8) {
                        Button("Restore…") { restoreFlow.choose(model: model) }
                        Button("Back Up Now", action: model.backUpNow)
                    }
                } label: {
                    Group {
                        if let last = model.lastBackup {
                            Text("Last backup \(Self.when(last))")
                        } else {
                            Text("No backups in this folder yet")
                        }
                    }
                    .foregroundStyle(.secondary)
                    if model.backupFailedAt != nil {
                        Text("The latest backup could not be saved in this folder.")
                    }
                }
            }
            Section("Import") {
                LabeledContent {
                    Button("Import…") { importFlow.choose(model: model) }
                } label: {
                    Text("Import from Daily")
                    Text("Uses the JSON export of activities and timesheet.")
                }
            }
        }
        .settingsPane()
        .dailyImport(importFlow, model: model)
        .restore(restoreFlow, model: model)
    }

    /// "today at 9:00", "Nov 5, 2026 at 9:00", for the middle of a sentence.
    static func when(_ date: Date) -> String {
        relative.string(from: date)
    }

    private static let relative: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        formatter.formattingContext = .middleOfSentence
        return formatter
    }()

    /// "iCloud Drive / Backups / maloche"; inside the home folder relative to it, on another volume from its name.
    static func folderName(_ path: String, home: String = NSHomeDirectory()) -> String {
        var parts = URL(filePath: path).pathComponents.filter { $0 != "/" }
        let homeParts = URL(filePath: home).pathComponents.filter { $0 != "/" }
        if let drive = parts.firstIndex(of: "com~apple~CloudDocs"), drive > 0, parts[drive - 1] == "Mobile Documents" {
            parts = [String(localized: "iCloud Drive")] + parts[(drive + 1)...]
        } else if parts.starts(with: homeParts) {
            parts.removeFirst(homeParts.count)
        } else if parts.first == "Volumes" {
            parts.removeFirst()
        }
        return parts.joined(separator: " / ")
    }

    /// From a click only, the open panel is modal.
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Choose the folder for your backups.")
        panel.prompt = String(localized: "Choose")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = model.backupFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.setting(\.backup.folder).wrappedValue = url.path(percentEncoded: false)
    }
}

/// Icon, name, version and the principle; the update settings only with an updater.
struct AboutSettingsView: View {
    let model: AppModel
    /// Nil in a bundle without updates, which then shows no update settings.
    var checkForUpdates: (() -> Void)?
    var info: [String: Any] = Bundle.main.infoDictionary ?? [:]

    static func version(info: [String: Any]) -> String {
        let version = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        return String(localized: "Version \(version) (\(build))")
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    Text("maloche")
                        .font(.title)
                        .fontDesign(.rounded)
                        .fontWeight(.semibold)
                    Text(Self.version(info: info))
                        .foregroundStyle(.secondary)
                    Text(
                        "Every now and then, maloche asks what you are working on. One answer, and your day fills itself."
                    )
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            if let checkForUpdates {
                Section {
                    HStack {
                        Toggle("Check for updates automatically", isOn: model.setting(\.checkForUpdates))
                        Spacer()
                        Button("Check Now", action: checkForUpdates)
                    }
                }
            }
        }
        .settingsPane()
    }
}

extension View {
    func settingsPane() -> some View {
        formStyle(.grouped)
            .scrollDisabled(true)
            .frame(width: SettingsWindowController.width)
            .fixedSize(horizontal: false, vertical: true)
    }
}
