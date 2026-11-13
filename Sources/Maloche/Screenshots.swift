#if DEBUG
    import AppKit
    import SwiftUI
    import MalocheCore

    /// Renders every screen with sample data in light and dark: `Maloche --screenshots <dir>`.
    @MainActor
    enum Screenshots {
        static var outputDirectory: URL? {
            let args = CommandLine.arguments
            guard let index = args.firstIndex(of: "--screenshots"), index + 1 < args.count else { return nil }
            return URL(filePath: args[index + 1], directoryHint: .isDirectory)
        }

        private struct FixedClock: WallClock {
            let now: Date
        }

        static func renderAll(to directory: URL) throws {
            let backupRoot = FileManager.default.temporaryDirectory.appending(
                path: "maloche-screenshots-\(UUID().uuidString)", directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: backupRoot) }
            try MenuBarIcon.writePreviews(to: directory)
            for screen in try screens(backupRoot: backupRoot) {
                for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    let url = directory.appending(path: "\(screen.name)-\(mode).png")
                    try render(screen.view, appearance: NSAppearance(named: appearance)!, to: url)
                    print(url.path(percentEncoded: false))
                }
            }
        }

        /// Every screen with sample data; the backup settings write into `backupRoot`.
        static func screens(backupRoot: URL) throws -> [(name: String, view: AnyView)] {
            let sample = try Sample()
            let model = sample.model
            let timed = CheckIn(
                mode: .timed, span: DateInterval(start: Sample.at(10, 15), end: Sample.at(10, 30)),
                prefill: sample.review)
            let long = CheckIn(
                mode: .timed, span: DateInterval(start: Sample.at(10, 15), end: Sample.at(11, 0)),
                prefill: sample.review, canSplit: true)
            func split(_ activities: [Int64?], at dividers: [(Int, Int)]) -> SplitDraft {
                let lists = activities.map { CheckInList(catalog: model.catalog, prefill: $0) }
                var draft = SplitDraft(span: long.span!, first: lists[0], second: lists[1])
                for list in lists.dropFirst(2) { draft.addPart(list) }
                for (index, time) in dividers.enumerated() { draft.moveDivider(index, to: Sample.at(time.0, time.1)) }
                return draft
            }
            func typed(_ text: String, projectId: Int64? = nil) -> CheckInList {
                var list = CheckInList(catalog: model.catalog, prefill: sample.review)
                list.setText(text)
                list.projectId = projectId
                return list
            }
            /// Default settings, changed by `edit`, never stored.
            func settings(_ edit: (inout AppSettings) -> Void = { _ in }) throws -> AppModel {
                let model = try AppModel(database: .inMemory(), stateURL: nil)
                var settings = model.settings
                edit(&settings)
                model.update(settings)
                return model
            }
            let managing = try Sample.managing()
            let mergeTargets = try managing.model.activityOverview().rows(.all)
                .filter { $0.id != managing.abstimmung }
                .sorted { $0.activity.name.localizedStandardCompare($1.activity.name) == .orderedAscending }
            let screens: [(name: String, view: AnyView)] = [
                ("checkin", AnyView(CheckInView(model: model, content: .checkIn(timed)))),
                (
                    "checkin-manual",
                    AnyView(
                        CheckInView(
                            model: model,
                            content: .checkIn(
                                CheckIn(
                                    mode: .manual, span: DateInterval(start: Sample.at(8, 30), end: Sample.at(10, 30)),
                                    prefill: sample.writing))))
                ),
                (
                    "checkin-first-answer",
                    AnyView(
                        CheckInView(
                            model: model,
                            content: .checkIn(
                                CheckIn(
                                    mode: .timed, span: DateInterval(start: Sample.at(8, 0), end: Sample.at(8, 45)),
                                    duration: 20 * 60, prefill: sample.writing))))
                ),
                (
                    "newactivity",
                    AnyView(CheckInView(model: model, content: .checkIn(timed), list: typed("Kickoff Relaunch")))
                ),
                (
                    "newactivity-project",
                    AnyView(
                        CheckInView(
                            model: model, content: .checkIn(timed),
                            list: typed("Kickoff Relaunch", projectId: sample.relaunch)))
                ),
                (
                    "newproject",
                    AnyView(
                        CheckInView(
                            model: model, content: .checkIn(timed), list: typed("Kickoff Relaunch"),
                            draft: ProjectDraft(name: "Relaunch 2027", customer: "Acme")))
                ),
                ("checkin-long", AnyView(CheckInView(model: model, content: .checkIn(long)))),
                (
                    "split",
                    AnyView(
                        CheckInView(
                            model: model, content: .checkIn(long),
                            split: split([sample.review, sample.weekly], at: [(10, 40)])))
                ),
                (
                    "split-three",
                    AnyView(
                        CheckInView(
                            model: model, content: .checkIn(long),
                            split: split([sample.review, sample.writing, sample.weekly], at: [(10, 30), (10, 45)])))
                ),
                (
                    "away-return",
                    AnyView(
                        CheckInView(
                            model: model,
                            content: .awayReturn(
                                span: DateInterval(start: Sample.at(10, 20), end: Sample.at(11, 5)),
                                prefill: model.builtIns.breakId)))
                ),
                (
                    "break-return",
                    AnyView(
                        CheckInView(
                            model: model,
                            content: .breakReturn(
                                span: DateInterval(start: Sample.at(12, 15), end: Sample.at(13, 0)),
                                prefill: sample.review)))
                ),
                (
                    "dashboard-day",
                    AnyView(DashboardView.sample(.activity(id: DashboardView.sampleCodeReviewId), model: model))
                ),
                (
                    "dashboard-few",
                    AnyView(DashboardView.sample(.activity(id: 5), few: true, model: model))
                ),
                ("dashboard-break", AnyView(DashboardView.sample(.onBreak, model: model))),
                ("dashboard-off", AnyView(DashboardView.sample(.off, model: model))),
                ("dashboard-empty", AnyView(DashboardView.sample(.none, empty: true, model: model))),
                ("dashboard-done", AnyView(DashboardView.sample(.doneForToday, model: model))),
                ("dashboard-week", AnyView(DashboardView.sample(.week, model: model))),
                ("dashboard-month", AnyView(DashboardView.sample(.month, model: model))),
                (
                    "settings-general",
                    AnyView(GeneralSettingsView(model: try settings(), isLoginItem: { true }))
                ),
                ("settings-schedule", AnyView(ScheduleSettingsView(model: try settings()))),
                (
                    "settings-rounding",
                    AnyView(RoundingSettingsView(model: try settings { $0.rounding.stepMinutes = 15 }))
                ),
                ("settings-backup", AnyView(BackupSettingsView(model: try Sample.backedUp(in: backupRoot)))),
                ("settings-about", AnyView(AboutSettingsView(model: try settings(), checkForUpdates: {}))),
                ("import-preview", AnyView(DailyImportView(preview: try Sample.dailyImport()) { _ in })),
                (
                    "welcome",
                    AnyView(WelcomeView(model: try settings(), openAtLogin: true, showsUpdates: true) { _, _ in })
                ),
                (
                    "manage-activities",
                    AnyView(
                        ManageActivitiesView(
                            model: managing.model, filter: .customer(managing.nordlicht),
                            selection: [managing.abstimmung]
                        )
                        .frame(
                            width: ManageActivitiesWindowController.size.width,
                            height: ManageActivitiesWindowController.size.height))
                ),
                (
                    "manage-merge",
                    AnyView(
                        MergeSheet(
                            names: ["Abstimmung"], moving: 90 * 60, targets: mergeTargets, target: managing.review
                        ) { _ in })
                ),
                (
                    "manage-new-activity",
                    AnyView(
                        NameSheet(
                            title: Text("New Activity"), detail: Text("In \("Relaunch 2026")"), action: Text("Create"),
                            name: "Code Review",
                            note: Text("“\("Code Review")” is already in use, choose another name.")
                        ) { _ in })
                ),
            ]
            return screens
        }

        /// Synthetic customers, projects, activities and today's blocks in an in-memory database, at 10:30.
        @MainActor private struct Sample {
            let model: AppModel
            let review: Int64?
            let writing: Int64?
            let weekly: Int64?
            let relaunch: Int64?
            static let today = Calendar.current.startOfDay(for: .now)

            static func at(_ hour: Int, _ minute: Int) -> Date {
                Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: today)!
            }

            init() throws {
                let database = try AppDatabase.inMemory()
                let acme = try database.createCustomer(name: "Acme")
                let northwind = try database.createCustomer(name: "Northwind")
                let relaunch = try database.createProject(name: "Relaunch", customerId: acme.id)
                _ = try database.createProject(name: "Maintenance", customerId: acme.id)
                let shop = try database.createProject(name: "Shop", customerId: northwind.id)
                _ = try database.createProject(name: "Internal tools", customerId: nil)
                let review = try database.createActivity(name: "Code Review", projectId: relaunch.id)
                let writing = try database.createActivity(name: "Writing")
                let weekly = try database.createActivity(name: "Weekly", customerId: northwind.id)
                let kickoff = try database.createActivity(name: "Kickoff Shop", projectId: shop.id)
                self.review = review.id
                self.writing = writing.id
                self.weekly = weekly.id
                self.relaunch = relaunch.id
                let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Self.today)!
                try database.insert(
                    block: Block(
                        activityId: kickoff.id!, startedAt: yesterday + 9 * 3600, endedAt: yesterday + 10 * 3600,
                        source: .checkIn))
                for (activity, start, end) in [
                    (weekly, (8, 30), (9, 0)), (writing, (9, 0), (10, 0)), (review, (10, 0), (10, 15)),
                ] {
                    try database.insert(
                        block: Block(
                            activityId: activity.id!, startedAt: Self.at(start.0, start.1),
                            endedAt: Self.at(end.0, end.1),
                            source: .checkIn))
                }
                model = try AppModel(
                    database: database, stateURL: nil, builtInNames: AppModel.localizedBuiltInNames,
                    clock: FixedClock(now: Self.at(10, 30)))
            }

            /// Two customers with projects and activities, time in this and the last month, Old Stuff archived, at 17:30.
            static func managing() throws -> (model: AppModel, nordlicht: Int64, abstimmung: Int64, review: Int64) {
                let database = try AppDatabase.inMemory()
                let nordlicht = try database.createCustomer(name: "Nordlicht GmbH")
                let hafenwerk = try database.createCustomer(name: "Hafenwerk AG")
                let relaunch = try database.createProject(name: "Relaunch 2026", customerId: nordlicht.id)
                let maintenance = try database.createProject(name: "Maintenance", customerId: nordlicht.id)
                let shop = try database.createProject(name: "Shop 2.0", customerId: hafenwerk.id)
                func activity(_ name: String, _ project: Project? = nil, customer: Customer? = nil) throws -> Int64 {
                    try database.createActivity(name: name, projectId: project?.id, customerId: customer?.id).id!
                }
                let review = try activity("Code Review", relaunch)
                let abstimmung = try activity("Abstimmung", relaunch)
                let templates = try activity("Frontend Templates", relaunch)
                let kickoff = try activity("Kickoff", relaunch)
                let backups = try activity("Backups prüfen", maintenance)
                let update = try activity("Server-Update", maintenance)
                _ = try activity("Checkout", shop)
                _ = try activity("Code Review", shop)
                let weekly = try activity("Weekly", customer: hafenwerk)
                let writing = try activity("Writing")
                let old = try activity("Old Stuff", relaunch)
                let bookings: [(Int64, Int, (Int, Int), (Int, Int))] = [
                    (review, 0, (8, 0), (10, 15)), (abstimmung, 0, (10, 15), (11, 45)), (writing, 0, (13, 0), (14, 0)),
                    (templates, 1, (9, 0), (12, 30)), (review, 1, (13, 0), (16, 0)), (weekly, 2, (9, 0), (9, 30)),
                    (backups, 6, (9, 0), (10, 15)), (update, 12, (9, 0), (11, 30)), (kickoff, 39, (9, 0), (12, 0)),
                    (old, 60, (9, 0), (10, 0)),
                ]
                for (id, daysAgo, start, end) in bookings {
                    let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: today)!
                    func time(_ clock: (Int, Int)) -> Date {
                        Calendar.current.date(bySettingHour: clock.0, minute: clock.1, second: 0, of: day)!
                    }
                    try database.insert(
                        block: Block(activityId: id, startedAt: time(start), endedAt: time(end), source: .checkIn))
                }
                try database.setArchived(true, activities: [old])
                let model = try AppModel(database: database, stateURL: nil, clock: FixedClock(now: at(17, 30)))
                return (model, nordlicht.id!, abstimmung, review)
            }

            /// Backed up today at 9:00 into a temporary folder laid out like one in iCloud Drive.
            static func backedUp(in root: URL) throws -> AppModel {
                let folder = root.appending(
                    path: "Library/Mobile Documents/com~apple~CloudDocs/Backups/maloche", directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let model = try AppModel(
                    database: .inMemory(), stateURL: nil, backups: folder, clock: FixedClock(now: at(9, 0)))
                model.backUpNow()
                return model
            }

            /// Prefixes and counts like the board, 556 activities and 70 days from September 1, an empty database.
            static func dailyImport() throws -> DailyImport {
                let prefixed = [("nordlicht", 42), ("hafenwerk", 18), ("kanzlei-b", 11), ("intern", 9), ("pf", 3)]
                let names =
                    prefixed.flatMap { prefix, count in Array(repeating: prefix, count: count) }.enumerated()
                    .map { "\($1) - Task \($0 + 1)" } + (1...473).map { "Topic \($0)" }
                func json(_ items: [String]) -> Data { Data("[\(items.joined(separator: ", "))]".utf8) }
                let activities = names.map {
                    #"{"name": "\#($0)", "group": null, "archived": false, "lastUsed": "2026-11-09T17:00:00Z"}"#
                }
                let first = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 1))!
                let days = (0..<70).map { offset in
                    let day = Calendar.current.date(byAdding: .day, value: offset, to: first)!
                    let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
                    let date = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
                    let started = (day + 8 * 3600).formatted(.iso8601)
                    return #"""
                        {"date": "\#(date)", "activities": [{"activity": "\#(names[offset])", "group": null, \#
                        "duration": 3600}], "info": {"started": "\#(started)"}}
                        """#
                }
                let export = try DailyExport(activities: json(activities), timesheet: json(days))
                var preview = try AppDatabase.inMemory().dailyImport(export, calendar: .current)
                for (index, name) in ["Nordlicht GmbH", "Hafenwerk AG", "Kanzlei Berger", "Intern", "Pf"].enumerated() {
                    preview.prefixes[index].customerName = name
                    preview.prefixes[index].isOn = index < 3
                }
                return preview
            }
        }

        private static func render(_ view: AnyView, appearance: NSAppearance, to url: URL) throws {
            guard let png = try image(of: view, appearance: appearance).representation(using: .png, properties: [:])
            else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path]) }
            try png.write(to: url)
            precondition(
                NSApp.keyWindow == nil && !NSApp.isActive && NSApp.windows.allSatisfy { !$0.isVisible },
                "screenshots must never take the keyboard or show a window")
        }

        /// Draws as an active window without ever becoming key, so the app in front keeps the keyboard.
        final class Window: NSWindow {
            init() {
                super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            }

            override var canBecomeKey: Bool { false }
            override var canBecomeMain: Bool { false }
            // controls and focus rings draw their active look from these, the window server is never asked
            override var isKeyWindow: Bool { true }
            override var isMainWindow: Bool { true }
        }

        /// The view in a window that is never shown; glass needs the window server, the panel background stands in.
        static func image(of view: AnyView, appearance: NSAppearance) throws -> NSBitmapImageRep {
            let hosting = NSHostingView(
                rootView: view.background(Color(nsColor: .windowBackgroundColor)).clipShape(.rect(cornerRadius: 16))
                    // the active look of a key panel, without the window ever becoming key
                    .environment(\.appearsActive, true))
            hosting.appearance = appearance
            hosting.frame.size = hosting.fittingSize
            let window = Window()
            window.appearance = appearance
            window.setContentSize(hosting.frame.size)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            // lets tasks such as the initial field focus run, the window stays off screen and never key
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            hosting.layoutSubtreeIfNeeded()
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                throw CocoaError(.fileWriteUnknown)
            }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            return rep
        }
    }
#endif
