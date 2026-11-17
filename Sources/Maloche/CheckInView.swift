import AppKit
import MalocheCore
import SwiftUI

/// The check-in and the returns after being away and after a break: a field with suggestions and Log.
struct CheckInView: View {
    let model: AppModel
    let content: PanelContent
    @State private var list: CheckInList
    @State private var split: SplitDraft?
    @State private var draft: ProjectDraft?
    /// The split part a new project is for, nil for the check-in field.
    @State private var draftPart: Int?
    @FocusState private var focusedField: Int?

    init(
        model: AppModel, content: PanelContent, list: CheckInList? = nil, split: SplitDraft? = nil,
        draft: ProjectDraft? = nil
    ) {
        self.model = model
        self.content = content
        let initial: CheckInList
        switch content {
        case .checkIn(let checkIn): initial = CheckInList(catalog: model.catalog, prefill: checkIn.prefill)
        case .awayReturn(_, let prefill):
            initial = CheckInList(catalog: model.catalog, prefill: prefill, includingBuiltIns: true)
        case .breakReturn(_, let prefill): initial = CheckInList(catalog: model.catalog, prefill: prefill)
        case .dashboard: initial = CheckInList(catalog: model.catalog, prefill: nil)
        }
        _list = State(initialValue: list ?? initial)
        _split = State(initialValue: split)
        _draft = State(initialValue: draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            // the child may still update after the optional turned nil, a force unwrapping Binding($draft) traps
            if let current = draft {
                NewProjectForm(
                    draft: Binding(get: { draft ?? current }, set: { if draft != nil { draft = $0 } }),
                    customers: model.catalog.customers, onCancel: { draft = nil }, onCreate: createProject)
            } else if let current = split {
                SplitView(
                    catalog: model.catalog,
                    split: Binding(get: { split ?? current }, set: { if split != nil { split = $0 } }),
                    onLog: logSplit, onBack: { split = nil },
                    onNewProject: { part, new in
                        draftPart = part
                        draft = new
                    })
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if let question {
                        Text(question).padding(.horizontal, 4)
                    }
                    ActivityField(
                        catalog: model.catalog, list: $list, focus: $focusedField, id: 0, onSubmit: log,
                        onEscape: model.close,
                        onNewProject: { new in
                            draftPart = nil
                            draft = new
                        }
                    )
                    // focus per appearance, a panel opened without key status still types into the field after a click
                    .task { focusedField = 0 }
                }
                if !list.rows.isEmpty {
                    SuggestionList(list: $list, catalog: model.catalog, sections: isCheckIn, onPick: log)
                }
                Divider().padding(.horizontal, 4)
                buttons
            }
        }
        .padding(12)
        .padding(.top, 6)
        .frame(width: 380)
        // a prompt asked again while open covers a longer span, the open split follows it
        .onChange(of: content) {
            if case .checkIn(let checkIn) = content, let span = checkIn.span { split = split?.spanning(span) }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle = subtitle(spoken: false) {
                    Text(subtitle)
                        .accessibilityLabel(self.subtitle(spoken: true) ?? subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
            if case .checkIn(let checkIn) = content, draft == nil {
                HStack(spacing: 4) {
                    if checkIn.canSplit {
                        Toggle("Split", isOn: Binding(get: { split != nil }, set: toggleSplit))
                            .toggleStyle(.button)
                            .buttonStyle(.accessoryBar)
                            .controlSize(.small)
                    }
                    MoreActionsMenu(model: model)
                }
            }
        }
        .padding(.leading, 4)
    }

    private var isCheckIn: Bool {
        if case .checkIn = content { true } else { false }
    }

    private var title: String {
        switch content {
        case .checkIn where split != nil: String(localized: "What were you working on?")
        case .checkIn: String(localized: "What are you working on?")
        case .awayReturn, .breakReturn, .dashboard: String(localized: "Welcome back")
        }
    }

    private func subtitle(spoken: Bool) -> String? {
        switch content {
        case .checkIn(let checkIn): checkIn.span.map { Self.since($0.start, checkIn.duration, spoken: spoken) }
        case .awayReturn(let span, _): Self.away(span, spoken: spoken)
        case .breakReturn(let span, _): Self.onBreak(span, spoken: spoken)
        case .dashboard: nil
        }
    }

    private var question: String? {
        switch content {
        case .checkIn, .dashboard: nil
        case .awayReturn: String(localized: "What was that time?")
        case .breakReturn: String(localized: "What are you working on now?")
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            if let hint {
                Text(hint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            switch content {
            case .checkIn where model.mode != .off: Button("Break", action: model.startBreak)
            case .checkIn, .awayReturn, .dashboard: EmptyView()
            case .breakReturn: Button("Still on break", action: model.close)
            }
            Button("Log", action: log)
                .keyboardShortcut(.defaultAction)
                .disabled(list.choice == nil)
        }
        .controlSize(.large)
        .keyCommand(.escape, modifiers: [], action: model.close)
    }

    private var hint: String? {
        guard list.isCreating, list.customerId == nil else { return nil }
        guard let project = model.catalog.project(list.projectId) else {
            return String(localized: "Tab picks a project")
        }
        return model.catalog.customer(project.customerId).map { String(localized: "\($0.name) comes with the project") }
    }

    private func log() {
        guard let choice = list.choice else { return NSSound.beep() }
        model.log(choice)
    }

    /// The first part keeps the activity before, the second takes the field unless it still names that one.
    private func toggleSplit(_ on: Bool) {
        guard on, case .checkIn(let checkIn) = content, let span = checkIn.span else {
            split = nil
            return
        }
        let first = CheckInList(catalog: model.catalog, prefill: checkIn.prefill)
        let second = list.choice == first.choice ? CheckInList(catalog: model.catalog, prefill: nil) : list
        split = SplitDraft(span: span, first: first, second: second)
    }

    private func logSplit() {
        if let split { model.log(split) }
    }

    private func createProject() {
        guard let draft else { return }
        do {
            if draft.forCustomer {
                let id = try model.createCustomer(name: draft.name).id
                if let draftPart { split?.parts[draftPart].customerId = id } else { list.customerId = id }
            } else {
                let id = try model.createProject(name: draft.name, customerName: draft.customer).id
                if let draftPart { split?.parts[draftPart].projectId = id } else { list.projectId = id }
            }
            self.draft = nil
        } catch {
            NSSound.beep()
        }
    }

    /// "1:45" on screen, "1 hour 45 minutes" for VoiceOver.
    private static func length(_ duration: TimeInterval, spoken: Bool) -> String? {
        spoken ? DurationText.spokenSpan(duration) : DurationText.span(duration)
    }

    static func since(_ start: Date, _ duration: TimeInterval, spoken: Bool = false) -> String {
        let time = start.formatted(date: .omitted, time: .shortened)
        guard let length = length(duration, spoken: spoken) else { return String(localized: "Since \(time)") }
        return String(localized: "Since \(time), \(length)")
    }

    static func away(_ span: DateInterval, spoken: Bool = false) -> String {
        let (start, end) = times(span)
        guard let length = length(span.duration, spoken: spoken) else {
            return String(localized: "Away from \(start) to \(end)")
        }
        return String(localized: "Away from \(start) to \(end), \(length)")
    }

    static func onBreak(_ span: DateInterval, spoken: Bool = false) -> String {
        let (start, end) = times(span)
        guard let length = length(span.duration, spoken: spoken) else {
            return String(localized: "Break from \(start) to \(end)")
        }
        return String(localized: "Break from \(start) to \(end), \(length)")
    }

    static func times(_ span: DateInterval) -> (String, String) {
        (span.start.formatted(date: .omitted, time: .shortened), span.end.formatted(date: .omitted, time: .shortened))
    }

    static func meta(project: String?, customer: String?) -> String {
        switch (project, customer) {
        case (let project?, let customer?): String(localized: "\(project), \(customer)")
        case (let name?, nil), (nil, let name?): name
        case (nil, nil): ""
        }
    }

    /// The name with its project or customer when another of the names is the same ignoring case.
    static func distinct(_ name: String, in place: String?, among names: [String]) -> String {
        guard let place, names.count(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) > 1 else {
            return name
        }
        return String(localized: "\(name) (\(place))")
    }
}

/// The activity field: arrows move the selected suggestion, Tab opens the project menu of a new activity.
struct ActivityField: View {
    let catalog: Catalog
    @Binding var list: CheckInList
    let focus: FocusState<Int?>.Binding
    let id: Int
    var label: String?
    let onSubmit: () -> Void
    let onEscape: () -> Void
    let onNewProject: (ProjectDraft) -> Void
    @State private var projectMenuRequest = 0

    var body: some View {
        HStack(spacing: 6) {
            TextField("Activity", text: Binding(get: { list.text }, set: { list.setText($0) }))
                .textFieldStyle(.plain)
                .focused(focus, equals: id)
                .accessibilityLabel(label ?? String(localized: "Activity"))
                .onSubmit(onSubmit)
                .onKeyPress(.downArrow) {
                    list.moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    list.moveSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.tab) {
                    guard list.isCreating else { return .ignored }
                    projectMenuRequest += 1
                    return .handled
                }
                .onKeyPress(.escape) {
                    onEscape()
                    return .handled
                }
            if list.isCreating {
                ProjectChip(
                    catalog: catalog, projectId: $list.projectId, customerId: $list.customerId,
                    menuRequest: $projectMenuRequest, onNew: onNewProject)
            } else if let match = list.fieldMatch {
                Text(CheckInView.meta(project: match.projectName, customer: match.customerName))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, list.isCreating ? 3 : 8)
        .fieldBackground(focused: focus.wrappedValue == id)
    }
}

/// The suggestions under a field, a click picks one; grouped into today and earlier when `sections` allows.
struct SuggestionList: View {
    @Binding var list: CheckInList
    let catalog: Catalog
    let sections: Bool
    let onPick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(list.rows.enumerated()), id: \.offset) { index, row in
                if let title = sectionTitle(at: index) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.top, index == 0 ? 0 : 6)
                        .padding(.bottom, 2)
                        .accessibilityAddTraits(.isHeader)
                }
                SuggestionRow(
                    row: row, selected: index == list.selection, catalog: catalog, projectId: list.projectId,
                    customerId: list.customerId
                )
                .onTapGesture {
                    list.select(index)
                    onPick()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Suggestions"))
    }

    private func sectionTitle(at index: Int) -> String? {
        guard sections, list.showsSections, case .activity(_, let today) = list.rows[index] else { return nil }
        if index > 0, case .activity(_, let previous) = list.rows[index - 1], previous == today { return nil }
        return today ? String(localized: "Today") : String(localized: "Earlier")
    }
}

private struct SuggestionRow: View {
    let row: CheckInList.Row
    let selected: Bool
    let catalog: Catalog
    let projectId: Int64?
    let customerId: Int64?

    private static let selectedText = Color(nsColor: .alternateSelectedControlTextColor)

    var body: some View {
        HStack(spacing: 8) {
            icon.frame(width: 12)
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(meta)
                .font(.subheadline)
                .lineLimit(1)
                .foregroundStyle(selected ? AnyShapeStyle(Self.selectedText.opacity(0.85)) : AnyShapeStyle(.secondary))
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .foregroundStyle(selected ? AnyShapeStyle(Self.selectedText) : AnyShapeStyle(.primary))
        .background(selected ? Color(nsColor: .controlAccentColor) : .clear, in: .rect(cornerRadius: 6))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }

    @ViewBuilder private var icon: some View {
        switch row {
        case .create:
            Image(systemName: "plus").fontWeight(.medium)
        case .activity(let suggestion, _) where suggestion.activity.kind != .regular:
            let square = RoundedRectangle(cornerRadius: 2)
            Group {
                if suggestion.activity.kind == .break {
                    square.fill(Color(nsColor: .tertiaryLabelColor))
                } else {
                    square.strokeBorder(Color(nsColor: .secondaryLabelColor), lineWidth: 1.5)
                }
            }
            .frame(width: 8, height: 8)
            .background {
                if selected { square.fill(Self.selectedText).padding(-1.5) }
            }
        case .activity(let suggestion, _):
            Circle()
                .fill(Color(nsColor: CustomerColor.nsColor(for: catalog.customer(of: suggestion.activity))))
                .frame(width: 8, height: 8)
                .background {
                    if selected { Circle().fill(Self.selectedText).padding(-1.5) }
                }
        }
    }

    private var title: String {
        switch row {
        case .create(let name): String(localized: "Create “\(name)”")
        case .activity(let suggestion, _): suggestion.activity.name
        }
    }

    private var meta: String {
        switch row {
        case .create:
            let project = catalog.project(projectId)
            return CheckInView.meta(
                project: project?.name, customer: catalog.customer(project?.customerId ?? customerId)?.name)
        case .activity(let suggestion, _):
            switch suggestion.activity.kind {
            case .break: return String(localized: "Not work time")
            case .private: return String(localized: "Not counted")
            case .regular: return CheckInView.meta(project: suggestion.projectName, customer: suggestion.customerName)
            }
        }
    }
}

extension View {
    /// The field look of the panel: 28 pt, corner radius 8, focus ring while the panel is key.
    func fieldBackground(focused: Bool) -> some View {
        modifier(FieldBackground(focused: focused))
    }
}

private struct FieldBackground: ViewModifier {
    let focused: Bool
    @Environment(\.appearsActive) private var appearsActive

    func body(content: Content) -> some View {
        content
            .frame(height: 28)
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)) }
            .overlay {
                if focused, appearsActive {
                    RoundedRectangle(cornerRadius: 11)
                        .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                        .padding(-3)
                }
            }
    }
}
