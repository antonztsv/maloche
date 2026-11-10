import AppKit
import SwiftUI
import WamaduCore

/// The check-in and the returns after being away and after a break: a field with suggestions and Log.
struct CheckInView: View {
    let model: AppModel
    let content: PanelContent
    @State private var list: CheckInList
    @State private var draft: ProjectDraft?
    @State private var projectMenuRequest = 0
    @FocusState private var fieldFocused: Bool

    init(model: AppModel, content: PanelContent, list: CheckInList? = nil, draft: ProjectDraft? = nil) {
        self.model = model
        self.content = content
        let initial: CheckInList
        switch content {
        case .checkIn(let checkIn): initial = CheckInList(catalog: model.catalog, prefill: checkIn.prefill)
        case .awayReturn(_, let prefill):
            initial = CheckInList(catalog: model.catalog, prefill: prefill, includingBuiltIns: true)
        case .breakReturn(_, let prefill): initial = CheckInList(catalog: model.catalog, prefill: prefill)
        }
        _list = State(initialValue: list ?? initial)
        _draft = State(initialValue: draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let binding = Binding($draft) {
                NewProjectForm(
                    draft: binding, customers: model.catalog.customers, onCancel: { draft = nil },
                    onCreate: createProject)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if let question {
                        Text(question).padding(.horizontal, 4)
                    }
                    field
                }
                if !list.rows.isEmpty { suggestions }
                Divider().padding(.horizontal, 4)
                buttons
            }
        }
        .padding(12)
        .padding(.top, 4)
        .frame(width: 380)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 4)
    }

    private var title: String {
        if case .checkIn = content {
            String(localized: "What are you working on?")
        } else {
            String(localized: "Welcome back")
        }
    }

    private var subtitle: String? {
        switch content {
        case .checkIn(let checkIn): checkIn.span.map(Self.since)
        case .awayReturn(let span, _): Self.away(span)
        case .breakReturn(let span, _): Self.onBreak(span)
        }
    }

    private var question: String? {
        switch content {
        case .checkIn: nil
        case .awayReturn: String(localized: "What was that time?")
        case .breakReturn: String(localized: "What are you working on now?")
        }
    }

    private var field: some View {
        HStack(spacing: 6) {
            TextField("Activity", text: Binding(get: { list.text }, set: { list.setText($0) }))
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .onSubmit(log)
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
                    model.close()
                    return .handled
                }
            if list.isCreating {
                ProjectChip(
                    catalog: model.catalog, projectId: $list.projectId, menuRequest: $projectMenuRequest,
                    onNewProject: { draft = ProjectDraft() })
            } else if let match = list.fieldMatch {
                Text(Self.meta(project: match.projectName, customer: match.customerName))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, list.isCreating ? 3 : 8)
        .fieldBackground(focused: fieldFocused)
        // focus per appearance, a panel opened without key status still types into the field after a click
        .task { fieldFocused = true }
    }

    private var suggestions: some View {
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
                    row: row, selected: index == list.selection, catalog: model.catalog, projectId: list.projectId
                )
                .onTapGesture {
                    list.select(index)
                    log()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Suggestions"))
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            if case .checkIn = content { MoreActionsMenu() }
            if let hint {
                Text(hint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            switch content {
            case .checkIn: Button("Break", action: model.startBreak)
            case .awayReturn: EmptyView()
            case .breakReturn: Button("Still on break", action: model.close)
            }
            Button("Log", action: log)
                .keyboardShortcut(.defaultAction)
                .disabled(list.choice == nil)
        }
        .controlSize(.large)
    }

    private func sectionTitle(at index: Int) -> String? {
        guard case .checkIn = content, list.showsSections, case .activity(_, let today) = list.rows[index] else {
            return nil
        }
        if index > 0, case .activity(_, let previous) = list.rows[index - 1], previous == today { return nil }
        return today ? String(localized: "Today") : String(localized: "Earlier")
    }

    private var hint: String? {
        guard list.isCreating else { return nil }
        guard let project = model.catalog.project(list.projectId) else {
            return String(localized: "Tab picks a project")
        }
        return model.catalog.customer(project.customerId).map { String(localized: "\($0.name) comes with the project") }
    }

    private func log() {
        if let choice = list.choice { model.log(choice) }
    }

    private func createProject() {
        guard let draft else { return }
        do {
            list.projectId = try model.createProject(name: draft.name, customerName: draft.customer).id
            self.draft = nil
        } catch {
            NSSound.beep()
        }
    }

    static func since(_ span: DateInterval) -> String {
        let time = span.start.formatted(date: .omitted, time: .shortened)
        guard let length = DurationText.span(span.duration) else { return String(localized: "Since \(time)") }
        return String(localized: "Since \(time), \(length)")
    }

    static func away(_ span: DateInterval) -> String {
        let (start, end) = times(span)
        guard let length = DurationText.span(span.duration) else {
            return String(localized: "Away from \(start) to \(end)")
        }
        return String(localized: "Away from \(start) to \(end), \(length)")
    }

    static func onBreak(_ span: DateInterval) -> String {
        let (start, end) = times(span)
        guard let length = DurationText.span(span.duration) else {
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
}

private struct SuggestionRow: View {
    let row: CheckInList.Row
    let selected: Bool
    let catalog: Catalog
    let projectId: Int64?

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
            return CheckInView.meta(project: project?.name, customer: catalog.customer(project?.customerId)?.name)
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
