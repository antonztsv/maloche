import AppKit
import MalocheCore
import SwiftUI

/// The Manage Activities window; opening it again brings the same window to the front.
@MainActor
final class ManageActivitiesWindowController {
    static let identifier = NSUserInterfaceItemIdentifier("manage-activities")
    static let size = NSSize(width: 820, height: 560)
    static let minSize = NSSize(width: 780, height: 420)

    private let model: AppModel
    let request = ManageActivitiesRequest()
    private(set) lazy var window = makeWindow()

    init(model: AppModel) {
        self.model = model
    }

    /// From Manage Activities… in the more menu, or from the day with its activity; a normal window needs the app active.
    func show(selecting activityId: Int64? = nil) {
        if let activityId { request.activity = activityId }
        window.bringToFront()
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: ManageActivitiesView(model: model, request: request))
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.identifier = Self.identifier
        window.title = String(localized: "Manage Activities")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(Self.size)
        window.contentMinSize = Self.minSize
        window.centerOnActiveScreen()
        return window
    }
}

/// The activity to select and scroll to, cleared once the window shows it.
@MainActor @Observable final class ManageActivitiesRequest {
    var activity: Int64?
}

/// Customers with their projects in the sidebar, the activities of the selected entry in the table.
struct ManageActivitiesView: View {
    typealias Filter = ActivityOverview.Filter

    enum Subject: Hashable {
        case activity(Int64)
        case project(Int64)
        case customer(Int64)
        case newActivity, newProject, newCustomer
    }

    enum Sheet: Hashable, Identifiable {
        case name(Subject)
        case merge([Int64])

        var id: Self { self }
    }

    let model: AppModel
    var request = ManageActivitiesRequest()
    @State private var filter: Filter
    @State private var selection: Set<Int64>
    @State private var query = ""
    @State private var overview = ActivityOverview(catalog: Catalog(), thisMonth: [])
    @State private var sheet: Sheet?
    /// Selected once the table shows the rows of the new filter, it drops a selection it cannot show.
    @State private var revealing: Int64?
    @FocusState private var searching: Bool

    init(
        model: AppModel, request: ManageActivitiesRequest = ManageActivitiesRequest(), filter: Filter = .all,
        selection: Set<Int64> = []
    ) {
        self.model = model
        self.request = request
        _filter = State(initialValue: filter)
        _selection = State(initialValue: selection)
    }

    /// "Today", "Yesterday" or the date in the system's medium style.
    private static let lastUsed: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 210)
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                table
                Divider()
                footer
            }
        }
        .frame(
            minWidth: ManageActivitiesWindowController.minSize.width, maxWidth: .infinity,
            minHeight: ManageActivitiesWindowController.minSize.height, maxHeight: .infinity
        )
        .onChange(of: model.catalog, initial: true) { reload() }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .name(let subject): nameSheet(subject)
            case .merge(let ids): mergeSheet(ids)
            }
        }
    }

    private func reload() {
        do {
            overview = try model.activityOverview()
        } catch {
            appLog.error("loading the activities failed: \(String(describing: error), privacy: .private)")
        }
        selection.formIntersection(overview.rows(filter).map(\.id))
    }

    // MARK: Sidebar

    private var sidebar: some View {
        let groups = overview.groups
        let customers = groups.filter { $0.customer != nil }
        let withoutCustomer = groups.last?.projects ?? []
        return List(selection: Binding<Filter?>(get: { filter }, set: { if let value = $0 { filter = value } })) {
            item(.all, Text("All Activities"), icon: Image(systemName: "tray.full"))
            if !customers.isEmpty {
                Section("Customers") {
                    ForEach(customers, id: \.customer?.id) { group in
                        if let customer = group.customer, let id = customer.id {
                            item(.customer(id), Text(customer.name), icon: swatch(customer))
                                .contextMenu {
                                    Button("Rename…") { sheet = .name(.customer(id)) }
                                    colorPicker(customer)
                                }
                            projects(group.projects, customer: customer)
                        }
                    }
                    item(.noCustomer, Text("No customer"), icon: swatch(nil))
                    projects(withoutCustomer, customer: nil)
                }
            } else if !withoutCustomer.isEmpty {
                Section("Projects") {
                    projects(withoutCustomer, customer: nil)
                }
            }
            Section("More") {
                item(.archived, Text("Archived"), icon: Image(systemName: "archivebox"))
            }
        }
        .listStyle(.sidebar)
        .onKeyPress(.return) {
            switch filter {
            case .customer(let id): sheet = .name(.customer(id))
            case .project(let id): sheet = .name(.project(id))
            default: return .ignored
            }
            return .handled
        }
    }

    private func projects(_ projects: [Project], customer: Customer?) -> some View {
        ForEach(projects) { project in
            if let id = project.id {
                item(.project(id), Text(project.name), icon: swatch(customer))
                    .padding(.leading, 16)
                    .contextMenu {
                        Button("Rename…") { sheet = .name(.project(id)) }
                    }
            }
        }
    }

    private func item(_ value: Filter, _ name: Text, icon: some View) -> some View {
        Label {
            name
        } icon: {
            icon.accessibilityHidden(true)
        }
        .badge(overview.count(value))
        .tag(value)
    }

    private func swatch(_ customer: Customer?) -> some View {
        CustomerSwatch(customer: customer)
    }

    private func colorPicker(_ customer: Customer) -> some View {
        Picker(
            "Color",
            selection: Binding(
                get: { customer.colorIndex },
                set: { index in
                    guard let id = customer.id, let color = CustomerColor(rawValue: index) else { return }
                    attempt { try model.manage { try $0.setColor(color, ofCustomer: id) } }
                })
        ) {
            ForEach(CustomerColor.allCases, id: \.self) { color in
                Label {
                    Text(color.name)
                } icon: {
                    Image(nsImage: NSImage.swatch(color.nsColor) ?? NSImage())
                }
                .tag(color.rawValue)
            }
        }
    }

    private var title: Text {
        switch filter {
        case .all: Text("All Activities")
        case .customer(let id): Text(model.catalog.customer(id)?.name ?? "")
        case .project(let id): Text(model.catalog.project(id)?.name ?? "")
        case .noCustomer: Text("No customer")
        case .archived: Text("Archived")
        }
    }

    // MARK: Table

    private var header: some View {
        HStack(spacing: 8) {
            title
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            SearchField(text: $query)
                .focused($searching)
                .frame(width: 200)
            Menu {
                Button("New Activity…") { sheet = .name(.newActivity) }
                    .disabled(filter == .archived)
                Button("New Project…") { sheet = .name(.newProject) }
                Button("New Customer…") { sheet = .name(.newCustomer) }
            } label: {
                Image(systemName: "plus")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help(Text("Add"))
            .accessibilityLabel(Text("Add"))
            .keyCommand("n") { if filter != .archived { sheet = .name(.newActivity) } }
            .keyCommand("f") { searching = true }
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: 52)
    }

    /// Shows the requested activity selected in the sidebar entry that lists it.
    private func showRequested(_ scroll: ScrollViewProxy) {
        guard let id = request.activity else { return }
        request.activity = nil
        // on the first open this runs before the catalog reload
        reload()
        guard let shown = overview.filter(showing: id) else { return }
        query = ""
        if filter == shown {
            reveal(id, scroll)
        } else {
            revealing = id
            filter = shown
        }
    }

    private func reveal(_ id: Int64, _ scroll: ScrollViewProxy) {
        selection = [id]
        scroll.scrollTo(id)
    }

    private var table: some View {
        ScrollViewReader { scroll in
            rows
                .onChange(of: request.activity, initial: true) { showRequested(scroll) }
                .onChange(of: filter) {
                    selection = []
                    if let id = revealing {
                        revealing = nil
                        reveal(id, scroll)
                    }
                }
        }
    }

    private var rows: some View {
        Table(overview.rows(filter, query: query), selection: $selection) {
            TableColumn("Activity") { row in
                Text(row.activity.name)
            }
            .width(min: 150, ideal: 190)
            TableColumn("Project") { row in
                Text(row.projectName ?? row.customerName ?? "")
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 150)
            TableColumn("This month") { row in
                Text(duration: row.thisMonth)
                    .monospacedDigit()
            }
            .width(min: 70, ideal: 90, max: 120)
            .alignment(.trailing)
            TableColumn("Last used") { row in
                Text(row.activity.lastUsedAt.map(Self.lastUsed.string(from:)) ?? "")
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 110, max: 160)
            .alignment(.trailing)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: Int64.self) { ids in
            if ids.count == 1, let id = ids.first {
                Button("Rename…") { sheet = .name(.activity(id)) }
            }
            if !ids.isEmpty { actions(for: ids) }
        } primaryAction: { ids in
            if ids.count == 1, let id = ids.first { sheet = .name(.activity(id)) }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            status
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            actions(for: selection)
                .disabled(selection.isEmpty)
        }
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 12))
    }

    private var status: Text {
        switch selection.count {
        case 0: Text("Double-click an activity to rename it.")
        case 1: Text("1 selected. Double-click to rename.")
        default: Text("\(selection.count) selected.")
        }
    }

    @ViewBuilder private func actions(for ids: Set<Int64>) -> some View {
        moveMenu(ids)
            .fixedSize()
        Button("Merge Into…") { sheet = .merge(Array(ids)) }
            .fixedSize()
        Group {
            if filter == .archived {
                Button("Unarchive") { archive(ids, false) }
            } else {
                Button("Archive") { archive(ids, true) }
            }
        }
        .fixedSize()
    }

    /// Every customer with its projects; No project under a customer assigns the customer directly.
    private func moveMenu(_ ids: Set<Int64>) -> some View {
        Menu("Move to Project") {
            Text("All logged time moves along, past entries included")
            ForEach(overview.groups, id: \.customer?.id) { group in
                Section {
                    Button {
                        move(ids, projectId: nil, customerId: group.customer?.id)
                    } label: {
                        menuLabel(Text("No project"), customer: group.customer)
                    }
                    ForEach(group.projects) { project in
                        Button {
                            move(ids, projectId: project.id, customerId: nil)
                        } label: {
                            menuLabel(Text(project.name), customer: group.customer)
                        }
                    }
                } header: {
                    if let customer = group.customer { Text(customer.name) } else { Text("No customer") }
                }
            }
        }
    }

    private func menuLabel(_ name: Text, customer: Customer?) -> some View {
        Label {
            name
        } icon: {
            Image(nsImage: NSImage.swatch(CustomerColor.nsColor(for: customer)) ?? NSImage())
        }
    }

    private func move(_ ids: Set<Int64>, projectId: Int64?, customerId: Int64?) {
        attempt { try model.manage { try $0.moveActivities(Array(ids), projectId: projectId, customerId: customerId) } }
    }

    private func archive(_ ids: Set<Int64>, _ archived: Bool) {
        attempt { try model.manage { try $0.setArchived(archived, activities: Array(ids)) } }
    }

    private func attempt(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            appLog.error("managing activities failed: \(String(describing: error), privacy: .private)")
            NSSound.beep()
        }
    }

    // MARK: Sheets

    private func nameSheet(_ subject: Subject) -> NameSheet {
        let catalog = model.catalog
        switch subject {
        case .activity(let id):
            return NameSheet(
                title: Text("Rename Activity"), action: Text("Rename"), name: catalog.activity(id)?.name ?? ""
            ) { name in
                try model.manage { try $0.renameActivity(id: id, to: name) }
            }
        case .project(let id):
            return NameSheet(
                title: Text("Rename Project"), action: Text("Rename"), name: catalog.project(id)?.name ?? ""
            ) { name in
                try model.manage { try $0.renameProject(id: id, to: name) }
            }
        case .customer(let id):
            return NameSheet(
                title: Text("Rename Customer"), action: Text("Rename"), name: catalog.customer(id)?.name ?? ""
            ) { name in
                try model.manage { try $0.renameCustomer(id: id, to: name) }
            }
        case .newActivity:
            let placement = ActivityOverview.placement(for: filter)
            let within = catalog.project(placement.projectId)?.name ?? catalog.customer(placement.customerId)?.name
            return NameSheet(
                title: Text("New Activity"), detail: within.map { Text("In \($0)") }, action: Text("Create")
            ) { name in
                var created: Activity?
                try model.manage {
                    created = try $0.createActivity(
                        name: name, projectId: placement.projectId, customerId: placement.customerId)
                }
                query = ""
                if let id = created?.id { selection = [id] }
            }
        case .newProject:
            let customerId = overview.customerOfNewProject(for: filter)
            return NameSheet(
                title: Text("New Project"), detail: catalog.customer(customerId).map { Text("For \($0.name)") },
                action: Text("Create")
            ) { name in
                var created: Project?
                try model.manage { created = try $0.createProject(name: name, customerId: customerId) }
                if let id = created?.id { filter = .project(id) }
            }
        case .newCustomer:
            return NameSheet(title: Text("New Customer"), action: Text("Create")) { name in
                var created: Customer?
                try model.manage { created = try $0.createCustomer(name: name) }
                if let id = created?.id { filter = .customer(id) }
            }
        }
    }

    private func mergeSheet(_ ids: [Int64]) -> MergeSheet {
        let blocks = (try? model.database.blocks(ofActivities: ids)) ?? []
        let targets = overview.rows(.all).filter { !ids.contains($0.id) }
            .sorted { $0.activity.name.localizedStandardCompare($1.activity.name) == .orderedAscending }
        return MergeSheet(
            names: ids.compactMap { model.catalog.activity($0)?.name },
            moving: blocks.reduce(0) { $0 + $1.interval.duration }, targets: targets
        ) { target in
            try model.merge(ids, into: target)
            selection = [target]
        }
    }
}

/// Asks for a name; a name already in use keeps the sheet open with a note.
struct NameSheet: View {
    let title: Text
    var detail: Text?
    let action: Text
    let commit: (String) throws -> Void
    @State private var name: String
    @State private var note: Text?
    @Environment(\.dismiss) private var dismiss

    init(
        title: Text, detail: Text? = nil, action: Text, name: String = "", note: Text? = nil,
        commit: @escaping (String) throws -> Void
    ) {
        self.title = title
        self.detail = detail
        self.action = action
        self.commit = commit
        _name = State(initialValue: name)
        _note = State(initialValue: note)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                title.font(.headline)
                detail?.font(.callout).foregroundStyle(.secondary)
            }
            TextField("Name", text: $name)
            note?.font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(action: save) { action }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func save() {
        do {
            try commit(name)
            dismiss()
        } catch MalocheError.duplicateName {
            note = Text("“\(trimmed)” is already in use, choose another name.")
        } catch {
            appLog.error("saving a name failed: \(String(describing: error), privacy: .private)")
            note = Text("The name was not saved, try again.")
        }
    }
}

/// Picks the activity to merge into and names the time that moves; the user asked for it, so Merge is the default.
struct MergeSheet: View {
    let names: [String]
    let moving: TimeInterval
    let targets: [ActivityOverview.Row]
    let merge: (Int64) throws -> Void
    @State private var target: Int64?
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    init(
        names: [String], moving: TimeInterval, targets: [ActivityOverview.Row], target: Int64? = nil,
        merge: @escaping (Int64) throws -> Void
    ) {
        self.names = names
        self.moving = moving
        self.targets = targets
        self.merge = merge
        _target = State(initialValue: target)
    }

    private var targetName: String? {
        targets.first { $0.id == target }.map(label)
    }

    private func label(_ row: ActivityOverview.Row) -> String {
        CheckInView.distinct(
            row.activity.name, in: row.projectName ?? row.customerName, among: targets.map(\.activity.name) + names)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if names.count == 1 { Text("Merge “\(names[0])”") } else { Text("Merge \(names.count) Activities") }
            }
            .font(.headline)
            Picker("Into", selection: $target) {
                Text("Choose an Activity").tag(Int64?.none)
                Divider()
                ForEach(targets) { row in
                    Text(label(row)).tag(Int64?.some(row.id))
                }
            }
            message(DurationFormat.hoursMinutes(moving))
                .accessibilityLabel(message(DurationFormat.spoken(moving)))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Merge", action: run)
                    .keyboardShortcut(.defaultAction)
                    .disabled(target == nil)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func message(_ time: String) -> Text {
        if failed {
            Text("The merge did not go through, nothing changed.")
        } else if let targetName {
            Text("\(time) of logged time moves to \(targetName). Afterwards only \(targetName) remains.")
        } else {
            Text("\(time) of logged time moves to the activity you choose.")
        }
    }

    private func run() {
        guard let target else { return }
        do {
            try merge(target)
            dismiss()
        } catch {
            appLog.error("merging activities failed: \(String(describing: error), privacy: .private)")
            failed = true
        }
    }
}

/// The system search field, SwiftUI has none outside the toolbar.
private struct SearchField: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = String(localized: "Search")
        field.cell?.setAccessibilityLabel(String(localized: "Search activities"))
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
    }

    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            text.wrappedValue = (notification.object as? NSSearchField)?.stringValue ?? ""
        }
    }
}
