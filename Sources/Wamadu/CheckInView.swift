import AppKit
import SwiftUI
import WamaduCore

struct CheckInView: View {
    let model: AppModel
    let checkIn: CheckIn
    @State private var list: CheckInList
    @FocusState private var fieldFocused: Bool

    init(model: AppModel, checkIn: CheckIn, list: CheckInList? = nil) {
        self.model = model
        self.checkIn = checkIn
        _list = State(initialValue: list ?? CheckInList(catalog: model.catalog, prefill: checkIn.prefill))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            field
            if !list.rows.isEmpty { suggestions }
            Divider().padding(.horizontal, 4)
            buttons
        }
        .padding(12)
        .padding(.top, 4)
        .frame(width: 380)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("What are you working on?")
                .font(.title3.weight(.semibold))
            if let span = checkIn.span {
                Text(Self.since(span))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 4)
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
                .onKeyPress(.escape) {
                    model.close()
                    return .handled
                }
            if let match = list.fieldMatch {
                Text(Self.meta(project: match.projectName, customer: match.customerName))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
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
                SuggestionRow(row: row, selected: index == list.selection, catalog: model.catalog)
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
            MoreActionsMenu()
            Spacer(minLength: 0)
            Button("Break", action: model.startBreak)
            Button("Log", action: log)
                .keyboardShortcut(.defaultAction)
                .disabled(list.choice == nil)
        }
        .controlSize(.large)
    }

    private func sectionTitle(at index: Int) -> String? {
        guard list.showsSections, case .activity(_, let today) = list.rows[index] else { return nil }
        if index > 0, case .activity(_, let previous) = list.rows[index - 1], previous == today { return nil }
        return today ? String(localized: "Today") : String(localized: "Earlier")
    }

    private func log() {
        if let choice = list.choice { model.log(choice) }
    }

    static func since(_ span: DateInterval) -> String {
        let time = span.start.formatted(date: .omitted, time: .shortened)
        guard let length = DurationText.span(span.duration) else { return String(localized: "Since \(time)") }
        return String(localized: "Since \(time), \(length)")
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
        case .create: ""
        case .activity(let suggestion, _):
            CheckInView.meta(project: suggestion.projectName, customer: suggestion.customerName)
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
