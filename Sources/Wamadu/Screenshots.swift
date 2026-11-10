#if DEBUG
    import AppKit
    import SwiftUI
    import WamaduCore

    /// Renders every screen with sample data in light and dark: `Wamadu --screenshots <dir>`.
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
            let sample = try Sample()
            let model = sample.model
            let timed = CheckIn(
                mode: .timed, span: DateInterval(start: Sample.at(10, 15), end: Sample.at(10, 30)),
                prefill: sample.review)
            func typed(_ text: String, projectId: Int64? = nil) -> CheckInList {
                var list = CheckInList(catalog: model.catalog, prefill: sample.review)
                list.setText(text)
                list.projectId = projectId
                return list
            }
            let screens: [(name: String, view: AnyView)] = [
                ("checkin", AnyView(CheckInView(model: model, checkIn: timed))),
                (
                    "checkin-manual",
                    AnyView(
                        CheckInView(
                            model: model,
                            checkIn: CheckIn(
                                mode: .manual, span: DateInterval(start: Sample.at(8, 30), end: Sample.at(10, 30)),
                                prefill: sample.writing)))
                ),
                ("newactivity", AnyView(CheckInView(model: model, checkIn: timed, list: typed("Kickoff")))),
                (
                    "newactivity-project",
                    AnyView(
                        CheckInView(model: model, checkIn: timed, list: typed("Kickoff", projectId: sample.relaunch)))
                ),
                (
                    "newproject",
                    AnyView(
                        CheckInView(
                            model: model, checkIn: timed, list: typed("Kickoff"),
                            draft: ProjectDraft(name: "Relaunch 2027", customer: "Acme")))
                ),
                ("dashboard-day", AnyView(DashboardView.sample(.activity(id: DashboardView.sampleCodeReviewId)))),
                ("dashboard-break", AnyView(DashboardView.sample(.onBreak))),
                ("dashboard-off", AnyView(DashboardView.sample(.off))),
                ("dashboard-empty", AnyView(DashboardView.sample(.none, empty: true))),
            ]
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for screen in screens {
                for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    let url = directory.appending(path: "\(screen.name)-\(mode).png")
                    try render(screen.view, appearance: NSAppearance(named: appearance)!, to: url)
                    print(url.path(percentEncoded: false))
                }
            }
        }

        /// Synthetic customers, projects, activities and today's blocks in an in-memory database, at 10:30.
        @MainActor private struct Sample {
            let model: AppModel
            let review: Int64?
            let writing: Int64?
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
                model = try AppModel(database: database, stateURL: nil, clock: FixedClock(now: Self.at(10, 30)))
            }
        }

        // Glass is composited by the window server and cannot be captured offscreen, the panel background stands in.
        private static func render(_ view: AnyView, appearance: NSAppearance, to url: URL) throws {
            let hosting = NSHostingView(
                rootView: view.background(Color(nsColor: .windowBackgroundColor)).clipShape(.rect(cornerRadius: 16)))
            hosting.appearance = appearance
            hosting.frame.size = hosting.fittingSize
            let window = CheckInPanel()
            window.setContentSize(hosting.frame.size)
            window.appearance = appearance
            window.contentView = hosting
            window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            window.makeKeyAndOrderFront(nil)
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
            }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            window.orderOut(nil)
            guard let png = rep.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
            }
            try png.write(to: url)
        }
    }
#endif
