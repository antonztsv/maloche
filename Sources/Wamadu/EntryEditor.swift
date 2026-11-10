import AppKit
import SwiftUI
import WamaduCore

/// The spans of one activity on the shown day: book them to another activity, change their times or delete them.
struct EntryEditorView: View {
    let model: AppModel
    let activityId: Int64
    let period: Period
    /// Done, Escape, and once the entry is gone after a move, a delete or a prompt in place of the dashboard;
    /// true hands the key status back to the dashboard.
    let onClose: (_ focusDashboard: Bool) -> Void
    @State private var confirmingDelete: Bool
    /// Typed times not yet committed.
    @State private var drafts: [Field: String] = [:]
    @FocusState private var focus: Field?

    struct Field: Hashable {
        var span: Int
        var end: Bool
    }

    init(
        model: AppModel, activityId: Int64, period: Period, confirmingDelete: Bool = false,
        onClose: @escaping (_ focusDashboard: Bool) -> Void
    ) {
        self.model = model
        self.activityId = activityId
        self.period = period
        self.onClose = onClose
        _confirmingDelete = State(initialValue: confirmingDelete)
    }

    /// Nil once the dashboard shows another day or the activity has no finished time left on it.
    private var entry: DayEntry? {
        guard case .dashboard(let day) = model.panel, day.period == period else { return nil }
        return model.entry(activityId: activityId)
    }

    private var name: String { model.catalog.activity(activityId)?.name ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let entry {
                if confirmingDelete { confirmation(entry) } else { editor(entry) }
            }
        }
        .padding(EdgeInsets(top: 14, leading: 12, bottom: 12, trailing: 12))
        .frame(width: 300)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Edit \(name)"))
        .onChange(of: entry == nil) { _, gone in
            // only a dashboard still shown takes the key status back, never a prompt in its place
            if gone { onClose(model.panel?.isPrompt == false) }
        }
        .onChange(of: focus) { left, _ in
            if let left { commit(left) }
        }
        .task { focus = Field(span: 0, end: false) }
        .keyCommand(.escape, modifiers: []) {
            if confirmingDelete { confirmingDelete = false } else { cancel() }
        }
    }

    @ViewBuilder private func editor(_ entry: DayEntry) -> some View {
        HStack(spacing: 8) {
            Text("Activity")
                .frame(maxWidth: .infinity, alignment: .leading)
            activityPicker
        }
        .padding(.horizontal, 2)
        VStack(spacing: 0) {
            ForEach(Array(entry.spans.enumerated()), id: \.offset) { index, span in
                if index > 0 { Divider() }
                spanRow(span, index: index)
            }
        }
        .background(Color(nsColor: .quaternarySystemFill), in: .rect(cornerRadius: 10))
        HStack(spacing: 8) {
            Button("Delete…", role: .destructive) {
                drafts = [:]
                confirmingDelete = true
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            Spacer()
            Button("Done", action: done)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
    }

    private var activityPicker: some View {
        let activities = model.catalog.activities.filter { $0.id != nil && (!$0.archived || $0.id == activityId) }
        let regular = activities.filter { $0.kind == .regular }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let names = regular.map(\.name)
        return Picker("Activity", selection: Binding(get: { activityId }, set: move)) {
            ForEach(regular) { activity in
                Label {
                    Text(
                        CheckInView.distinct(
                            activity.name,
                            in: model.catalog.project(activity.projectId)?.name
                                ?? model.catalog.customer(of: activity)?.name,
                            among: names))
                } icon: {
                    Image(
                        nsImage: NSImage.swatch(CustomerColor.nsColor(for: model.catalog.customer(of: activity)))
                            ?? NSImage())
                }
                .tag(activity.id!)
            }
            Divider()
            ForEach(activities.filter { $0.kind != .regular }) { activity in
                Text(activity.name).tag(activity.id!)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
    }

    private func spanRow(_ span: DayEntry.Span, index: Int) -> some View {
        HStack(spacing: 6) {
            timeField(
                Field(span: index, end: false), value: span.interval.start, label: Text("Start of part \(index + 1)"))
            Text("to")
                .foregroundStyle(.secondary)
            timeField(Field(span: index, end: true), value: span.interval.end, label: Text("End of part \(index + 1)"))
            Text(duration: span.interval.duration)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            ControlGroup {
                Button("−15") { extend(index, by: -15 * 60) }
                    .help(Text("15 minutes less"))
                    .accessibilityLabel(Text("15 minutes less"))
                Button("+15") { extend(index, by: 15 * 60) }
                    .help(Text("15 minutes more"))
                    .accessibilityLabel(Text("15 minutes more"))
            }
            .controlSize(.small)
            .fixedSize()
        }
        .monospacedDigit()
        .padding(.horizontal, 8)
        .frame(minHeight: 36)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Part \(index + 1)"))
    }

    /// As wide as the widest time of the clock format, centered like the board.
    private func timeField(_ field: Field, value: Date, label: Text) -> some View {
        Text(verbatim: Self.widestTime)
            .hidden()
            .padding(.horizontal, 6)
            .fixedSize()
            .overlay {
                TextField(
                    text: Binding(
                        get: { drafts[field] ?? value.formatted(DashboardData.time) }, set: { drafts[field] = $0 }),
                    prompt: Text(verbatim: "")
                ) { label }
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .multilineTextAlignment(.center)
                .focused($focus, equals: field)
                .onSubmit(done)
                .onKeyPress(.escape) {
                    cancel()
                    return .handled
                }
            }
    }

    private static let widestTime = Calendar.current.date(bySettingHour: 22, minute: 22, second: 0, of: .now)!
        .formatted(DashboardData.time)

    @ViewBuilder private func confirmation(_ entry: DayEntry) -> some View {
        let total = entry.spans.reduce(0) { $0 + $1.interval.duration }
        VStack(alignment: .leading, spacing: 4) {
            Text("Delete “\(name)”?")
                .font(.body.weight(.semibold))
            Self.timeOnDay(DashboardData.duration(total), entry.day)
                .accessibilityLabel(Self.timeOnDay(DashboardData.spoken(total), entry.day))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 2)
        HStack(spacing: 8) {
            Spacer()
            Button("Delete", role: .destructive) { model.deleteEntry(entry) }
                .foregroundStyle(.red)
            Button("Cancel") { confirmingDelete = false }
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
    }

    private static func timeOnDay(_ time: String, _ day: DateInterval) -> Text {
        Text(
            "\(time) on \(day.start, format: .dateTime.weekday(.wide).month(.wide).day())",
            comment: "The time of an entry and its day, below the question whether to delete it")
    }

    private func done() {
        if commitDrafts() { onClose(true) }
    }

    private func cancel() {
        drafts = [:]
        onClose(true)
    }

    private func extend(_ index: Int, by seconds: TimeInterval) {
        guard commitDrafts(), let entry, index < entry.spans.count else { return }
        model.extendSpan(entry.spans[index], of: entry, by: seconds)
    }

    private func move(to id: Int64) {
        guard id != activityId, commitDrafts(), let entry else { return }
        model.moveEntry(entry, to: id)
    }

    /// False when a typed time was refused, it reverts.
    private func commitDrafts() -> Bool {
        Array(drafts.keys).map(commit).allSatisfy { $0 }
    }

    @discardableResult private func commit(_ field: Field) -> Bool {
        guard let text = drafts.removeValue(forKey: field) else { return true }
        guard let entry, field.span < entry.spans.count else { return false }
        let span = entry.spans[field.span]
        let old = field.end ? span.interval.end : span.interval.start
        guard text != old.formatted(DashboardData.time) else { return true }
        guard
            let time = ClockTime.date(
                from: text, onDayOf: old, calendar: model.calendar, locale: .autoupdatingCurrent)
        else {
            model.presenter?.signalFailure()
            return false
        }
        guard time != old else { return true }
        model.setSpan(
            span, of: entry, start: field.end ? span.interval.start : time, end: field.end ? time : span.interval.end)
        return self.entry != entry
    }
}

/// The entry editor as a child panel of the dashboard beside the clicked row or block, closing like a popover.
@MainActor
final class EntryEditorController {
    let panel = CheckInPanel(cornerRadius: 14)
    private let model: AppModel
    private var hosting: NSView?
    /// The clicked row or block in screen coordinates.
    private var anchor = CGRect.zero

    init(model: AppModel) {
        self.model = model
        panel.onCancel = { [weak self] in self?.close() }
    }

    var isVisible: Bool { panel.isVisible }

    func show(activityId: Int64, anchor: CGRect, parent: NSWindow) {
        guard case .dashboard(let day) = model.panel, model.entry(activityId: activityId) != nil else { return }
        close(focusDashboard: false)
        let view = NSHostingView(
            rootView: EntryEditorView(model: model, activityId: activityId, period: day.period) { [weak self] in
                self?.close(focusDashboard: $0)
            }
            .onGeometryChange(for: CGSize.self) {
                $0.size
            } action: { [weak self] _ in
                DispatchQueue.main.async { self?.place() }
            })
        panel.glass.contentView = view
        hosting = view
        self.anchor = anchor
        parent.addChildWindow(panel, ordered: .above)
        place()
        panel.makeKeyAndOrderFront(nil)
    }

    /// Hands the key status back to the dashboard first, without a key panel of the app both would close.
    func close(focusDashboard: Bool = true) {
        guard let parent = panel.parent else { return }
        if focusDashboard, panel.isKeyWindow { parent.makeKey() }
        parent.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func place() {
        guard let hosting, let screen = panel.parent?.screen ?? NSScreen.main else { return }
        panel.setFrame(
            PanelPlacement.editorFrame(
                size: hosting.fittingSize, below: anchor, visibleFrame: screen.visibleFrame, margin: 6),
            display: true)
    }
}
