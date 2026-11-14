import AppKit
import MalocheCore
import SwiftUI

/// The span as a bar with draggable dividers and one activity field per part; Return books all parts.
struct SplitView: View {
    let catalog: Catalog
    @Binding var split: SplitDraft
    let onLog: () -> Void
    let onBack: () -> Void
    let onNewProject: (Int) -> Void
    @FocusState private var focusedPart: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SplitBar(split: $split, fills: split.parts.map(fill), names: split.parts.map(name), onBack: onBack)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(split.parts.indices, id: \.self) { part in
                    row(part)
                    let list = split.parts[part]
                    if focusedPart == part, list.fieldMatch == nil, !list.rows.isEmpty {
                        SuggestionList(list: $split.parts[part], catalog: catalog, sections: false) { pick(part) }
                            .padding(.leading, 16)
                    }
                }
                Button("Add another part") {
                    split.addPart(CheckInList(catalog: catalog, prefill: nil))
                    focusedPart = split.parts.count - 1
                }
                .buttonStyle(.link)
                .disabled(!split.canAddPart)
                .padding(.leading, 20)
            }
            Divider().padding(.horizontal, 4)
            HStack(spacing: 8) {
                Text("Drag the divider to adjust")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button("Log", action: onLog)
                    .keyboardShortcut(.defaultAction)
                    .disabled(split.choices == nil)
            }
            .padding(.leading, 4)
            .controlSize(.large)
            .keyCommand(.escape, modifiers: [], action: onBack)
        }
        .task { focusedPart = split.parts.count - 1 }
    }

    private func row(_ part: Int) -> some View {
        let interval = split.intervals[part]
        let span = String(
            localized: "\(interval.start, format: DashboardData.time) to \(interval.end, format: DashboardData.time)")
        return HStack(spacing: 8) {
            PartSwatch(fill: fill(split.parts[part]))
            ActivityField(
                catalog: catalog, list: $split.parts[part], focus: $focusedPart, id: part,
                label: String(localized: "Activity for \(span)"), onSubmit: onLog, onEscape: onBack,
                onNewProject: { onNewProject(part) })
            Text(DurationText.span(interval.duration) ?? "")
                .accessibilityLabel(DurationText.spokenSpan(interval.duration) ?? "")
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Part \(part + 1), \(span)"))
    }

    /// A picked activity fills the field, so the list closes.
    private func pick(_ part: Int) {
        if case .existing(let id) = split.parts[part].choice, let name = catalog.activity(id)?.name {
            split.parts[part].setText(name)
        }
    }

    /// The customer color of the chosen activity, nil for Break, which is hatched.
    private func fill(_ list: CheckInList) -> Color? {
        switch list.choice {
        case .existing(let id):
            guard let activity = catalog.activity(id) else { return Color(nsColor: .quaternaryLabelColor) }
            switch activity.kind {
            case .break: return nil
            case .private: return Color(nsColor: .quaternaryLabelColor)
            case .regular: return DashboardData.color(of: catalog.customer(of: activity))
            }
        case .create(_, let projectId):
            return DashboardData.color(of: catalog.customer(catalog.project(projectId)?.customerId))
        case nil:
            return Color(nsColor: .quaternaryLabelColor)
        }
    }

    private func name(_ list: CheckInList) -> String {
        switch list.choice {
        case .existing(let id): catalog.activity(id)?.name ?? list.text
        case .create(let name, _): name
        case nil: list.text
        }
    }
}

private struct PartSwatch: View {
    let fill: Color?

    var body: some View {
        if let fill {
            RoundedRectangle(cornerRadius: 2).fill(fill).frame(width: 8, height: 8).accessibilityHidden(true)
        } else {
            BreakSwatch()
        }
    }
}

/// The parts in their colors with the times below; arrow keys and VoiceOver move the focused divider by a minute.
private struct SplitBar: View {
    @Binding var split: SplitDraft
    let fills: [Color?]
    let names: [String]
    let onBack: () -> Void
    @FocusState private var focusedDivider: Int?

    private static let barHeight: CGFloat = 28
    private static let space = "splitBar"

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                Canvas(rendersAsynchronously: false) { context, size in draw(in: context, size: size) }
                    .accessibilityElement()
                    .accessibilityLabel(Text(verbatim: description))
                    .accessibilityAddTraits(.isImage)
                ForEach(split.dividers.indices, id: \.self) { index in
                    handle(index, width: width)
                        .position(x: x(of: split.dividers[index], width: width), y: Self.barHeight / 2)
                }
            }
            .coordinateSpace(.named(Self.space))
        }
        .frame(height: Self.barHeight + 4 + 13)
        .padding(.horizontal, 4)
    }

    /// "10:15 to 10:37 Code Review, 10:37 to 11:00 Writing"
    private var description: String {
        zip(split.intervals, names).map(DashboardData.spanLabel)
            .joined(separator: ", ")
    }

    private func x(of date: Date, width: CGFloat) -> CGFloat {
        guard split.span.duration > 0 else { return 0 }
        return date.timeIntervalSince(split.span.start) / split.span.duration * width
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        let intervals = split.intervals
        for (index, interval) in intervals.enumerated() {
            let minX = x(of: interval.start, width: size.width) + (index == 0 ? 0 : 1)
            let maxX = x(of: interval.end, width: size.width) - (index == intervals.count - 1 ? 0 : 1)
            let rect = CGRect(x: minX, y: 0, width: max(maxX - minX, 1), height: Self.barHeight)
            let path = Path(roundedRect: rect, cornerRadius: 4)
            if let fill = fills[index] {
                context.fill(path, with: .color(fill))
            } else {
                TimelineChart.hatch(path, in: rect, context: context)
            }
        }
        let top = Self.barHeight + 4
        func label(_ date: Date, divider: Bool) -> GraphicsContext.ResolvedText {
            context.resolve(
                Text(date, format: DashboardData.time)
                    .font(divider ? .caption.weight(.semibold) : .caption)
                    .monospacedDigit()
                    .foregroundStyle(Color(nsColor: divider ? .labelColor : .secondaryLabelColor)))
        }
        var occupied: [ClosedRange<CGFloat>] = []
        for divider in split.dividers {
            let text = label(divider, divider: true)
            let half = text.measure(in: size).width / 2
            let center = min(max(x(of: divider, width: size.width), half), size.width - half)
            context.draw(text, at: CGPoint(x: center, y: top), anchor: .top)
            occupied.append((center - half - 4)...(center + half + 4))
        }
        // the ends make way for a divider time close to them
        let start = label(split.span.start, divider: false)
        if !occupied.contains(where: { $0.overlaps(0...start.measure(in: size).width) }) {
            context.draw(start, at: CGPoint(x: 0, y: top), anchor: .topLeading)
        }
        let end = label(split.span.end, divider: false)
        if !occupied.contains(where: { $0.overlaps((size.width - end.measure(in: size).width)...size.width) }) {
            context.draw(end, at: CGPoint(x: size.width, y: top), anchor: .topTrailing)
        }
    }

    private func handle(_ index: Int, width: CGFloat) -> some View {
        Capsule()
            .fill(Color(nsColor: .alternateSelectedControlTextColor))
            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            .frame(width: 6, height: Self.barHeight + 6)
            .shadow(radius: 2, y: 1)
            .overlay {
                if focusedDivider == index {
                    Capsule()
                        .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                        .padding(-3)
                }
            }
            .frame(width: 16, height: Self.barHeight + 6)
            .contentShape(.rect)
            .pointerStyle(.columnResize)
            .focusable(interactions: .edit)
            .focused($focusedDivider, equals: index)
            .focusEffectDisabled()
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)).onChanged { value in
                    focusedDivider = index
                    let fraction = min(max(value.location.x / max(width, 1), 0), 1)
                    split.moveDivider(index, to: split.span.start + fraction * split.span.duration)
                }
            )
            .onKeyPress(.leftArrow) {
                split.moveDivider(index, by: -1)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                split.moveDivider(index, by: 1)
                return .handled
            }
            .onKeyPress(.escape) {
                onBack()
                return .handled
            }
            .accessibilityRepresentation {
                Slider(value: minutes(of: index), in: 0...split.span.duration / 60, step: 1) {
                    Text("Divider between \(partName(index)) and \(partName(index + 1))")
                }
                .accessibilityValue(Text(split.dividers[index], format: DashboardData.time))
            }
    }

    /// The divider's minutes from the start, VoiceOver moves it a minute per step.
    private func minutes(of index: Int) -> Binding<Double> {
        Binding {
            split.dividers[index].timeIntervalSince(split.span.start) / 60
        } set: { minutes in
            split.moveDivider(index, to: split.span.start + minutes * 60)
        }
    }

    private func partName(_ index: Int) -> String {
        names[index].isEmpty ? String(localized: "part \(index + 1)") : names[index]
    }
}
