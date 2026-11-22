#if DEBUG
    import AppKit
    import SwiftUI
    import MalocheCore

    /// Renders every screen with sample data in light and dark, and the README images into `readme/`:
    /// `Maloche --screenshots <dir>`.
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
            let screens = try screens(backupRoot: backupRoot)
            for screen in screens {
                for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    let url = directory.appending(path: "\(screen.name)-\(mode).png")
                    try render(screen.view, appearance: NSAppearance(named: appearance)!, to: url)
                }
            }
            try renderReadme(from: screens, to: directory.appending(path: "readme", directoryHint: .isDirectory))
        }

        /// The app icon at 128 pt and the check-in beside the day, dark, on a desktop with an empty menu bar.
        static func renderReadme(from screens: [(name: String, view: AnyView)], to directory: URL) throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let dark = NSAppearance(named: .darkAqua)!
            let panels = ["checkin", "dashboard-day"].compactMap { name in screens.first { $0.name == name }?.view }
            try write(
                image(of: AnyView(Desktop(panels: panels)), appearance: dark, panel: false),
                to: directory.appending(path: "hero.png"))
            let icon = try bitmap(pixels: 256)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: icon)
            NSApp.applicationIconImage.draw(in: NSRect(origin: .zero, size: icon.size))
            NSGraphicsContext.restoreGraphicsState()
            try write(icon, to: directory.appending(path: "icon.png"))
        }

        /// A transparent @2x bitmap of `pixels` square.
        private static func bitmap(pixels: Int) throws -> NSBitmapImageRep {
            guard
                let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                    bitsPerPixel: 0)
            else { throw CocoaError(.fileWriteUnknown) }
            rep.size = NSSize(width: pixels / 2, height: pixels / 2)
            return rep
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
            func typed(_ text: String, projectId: Int64? = nil, customerId: Int64? = nil) -> CheckInList {
                var list = CheckInList(catalog: model.catalog, prefill: sample.review)
                list.setText(text)
                list.projectId = projectId
                list.customerId = customerId
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
                    "newactivity-customer",
                    AnyView(
                        CheckInView(
                            model: model, content: .checkIn(timed),
                            list: typed("Support Acme", customerId: model.catalog.customers.first?.id)))
                ),
                (
                    "newcustomer",
                    AnyView(
                        CheckInView(
                            model: model, content: .checkIn(timed), list: typed("Support Acme"),
                            draft: ProjectDraft(name: "Hafenwerk", forCustomer: true)))
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
                    "dashboard-day-hover",
                    AnyView(
                        {
                            var view = DashboardView.sample(
                                .activity(id: DashboardView.sampleCodeReviewId), model: model)
                            view.hoveredEntry = 0
                            return view
                        }())
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
            try write(image(of: view, appearance: appearance), to: url)
        }

        private static func write(_ image: NSBitmapImageRep, to url: URL) throws {
            guard let png = image.representation(using: .png, properties: [:])
            else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path]) }
            try png.write(to: url)
            print(url.path(percentEncoded: false))
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

        /// The view in a window that is never shown, as a panel unless the view draws its own panels on a transparent
        /// background.
        static func image(of view: AnyView, appearance: NSAppearance, panel: Bool = true) throws -> NSBitmapImageRep {
            let hosting = NSHostingView(
                rootView: (panel ? AnyView(view.panel()) : view)
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

    /// A desktop cut-out for the README: a drawn wallpaper below an empty menu bar, the panels side by side.
    private struct Desktop: View {
        let panels: [AnyView]

        private static let menuBarHeight: CGFloat = 24

        var body: some View {
            HStack(alignment: .top, spacing: 40) {
                ForEach(panels.indices, id: \.self) { index in
                    panels[index].panel().shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                }
            }
            .padding(.top, Self.menuBarHeight + 6)
            .padding([.horizontal, .bottom], 56)
            .background(alignment: .top) {
                Rectangle().fill(.black.opacity(0.3)).frame(height: Self.menuBarHeight)
            }
            .background { Wallpaper() }
            .clipShape(.rect(cornerRadius: 16))
            .environment(\.colorScheme, .dark)
        }
    }

    /// Soft night-blue, violet and orange light in the manner of a macOS wallpaper, drawn rather than loaded.
    private struct Wallpaper: View {
        var body: some View {
            Canvas { context, size in
                let full = CGRect(origin: .zero, size: size)
                context.fill(
                    Path(full),
                    with: .linearGradient(
                        Gradient(colors: [Color(nsColor: .systemIndigo), Color(nsColor: .systemPurple)]),
                        startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
                // system colors darkened to night tones, the app defines no colors of its own
                context.fill(Path(full), with: .color(.black.opacity(0.72)))
                for (x, y, radius, color) in [
                    (0.15, 0.85, 0.75, NSColor.systemPurple),
                    (0.85, 0.20, 0.65, .systemBlue),
                    (0.70, 1.00, 0.55, .systemOrange),
                ] {
                    let center = CGPoint(x: size.width * x, y: size.height * y)
                    let reach = max(size.width, size.height) * radius
                    context.fill(
                        Path(full),
                        with: .radialGradient(
                            Gradient(colors: [Color(nsColor: color).opacity(0.45), Color(nsColor: color).opacity(0)]),
                            center: center, startRadius: 0, endRadius: reach))
                }
                for (index, opacity) in [0.10, 0.07, 0.05].enumerated() {
                    let base = size.height * (0.45 + 0.15 * Double(index))
                    var wave = Path()
                    wave.move(to: CGPoint(x: 0, y: base))
                    wave.addCurve(
                        to: CGPoint(x: size.width, y: base - size.height * 0.2),
                        control1: CGPoint(x: size.width * 0.35, y: base - size.height * 0.35),
                        control2: CGPoint(x: size.width * 0.65, y: base + size.height * 0.25))
                    wave.addLine(to: CGPoint(x: size.width, y: size.height))
                    wave.addLine(to: CGPoint(x: 0, y: size.height))
                    wave.closeSubpath()
                    context.fill(wave, with: .color(.white.opacity(opacity)))
                }
            }
        }
    }

    extension View {
        /// Glass needs the window server, the panel background stands in.
        fileprivate func panel() -> some View {
            background(Color(nsColor: .windowBackgroundColor)).clipShape(.rect(cornerRadius: 16))
        }
    }
#endif
