import AppKit
import MalocheCore
import SwiftUI

/// The day as blocks in customer colors with breaks hatched on a track, above an axis of full hours; the pointer snaps
/// to the nearest block, which shows a ring and its tooltip, a right click offers to delete it.
struct TimelineChart: View {
    var data: DashboardData
    var timeline: DayTimeline
    /// The activity of the clicked block.
    var onSelect: (Int64) -> Void = { _ in }
    /// The confirmed deletion of an entry.
    var onDelete: (DayTimeline.Segment<Int64>) -> Void = { _ in }
    /// The bar the pointer snaps to.
    @State var hovered: Int?
    @State private var deleting: DayTimeline.Segment<Int64>?
    @State private var width: CGFloat = 0

    private static let snapRadius: CGFloat = 8

    private static let barHeight: CGFloat = 24
    private static let axisTop: CGFloat = barHeight + 4

    var body: some View {
        Canvas { context, size in
            let track = CGRect(x: 0, y: 0, width: size.width, height: Self.barHeight)
            let trackPath = Path(roundedRect: track, cornerRadius: 4)
            context.fill(trackPath, with: .color(Color(nsColor: .quaternarySystemFill)))
            context.contrastEdge(trackPath, contrast: context.environment.colorSchemeContrast)
            for bar in data.bars {
                let minX = bar.start * size.width + 1
                let rect = CGRect(
                    x: minX, y: 0, width: max(bar.end * size.width - 1 - minX, 1), height: Self.barHeight)
                let path = Path(roundedRect: rect, cornerRadius: 4)
                if data.isBreak(bar.key) {
                    Self.hatch(path, in: rect, context: context)
                } else {
                    context.fill(path, with: .color(DashboardData.color(of: data.customer(of: bar.key))))
                }
            }
            func label(_ hour: Date) -> GraphicsContext.ResolvedText {
                context.resolve(
                    Text(hour, format: DashboardData.time).font(.caption).monospacedDigit()
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor)))
            }
            let labelWidth = timeline.fullHours(calendar: data.calendar).map { label($0).measure(in: size).width }.max()
            let half = (labelWidth ?? 0) / 2
            for tick in timeline.hourTicks(calendar: data.calendar, width: size.width, labelWidth: labelWidth ?? 0) {
                let x = min(max(timeline.fraction(of: tick) * size.width, half), size.width - half)
                context.draw(label(tick), at: CGPoint(x: x, y: Self.axisTop), anchor: .top)
            }
        }
        .frame(height: Self.axisTop + 14)
        .overlay(alignment: .topLeading) {
            if let hovered, data.bars.indices.contains(hovered) {
                let bar = data.bars[hovered]
                let minX = bar.start * width + 1
                // 2 pt apart from the block, 2 pt wide
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: max(bar.end * width - 1 - minX, 1) + 8, height: Self.barHeight + 8)
                    .offset(x: minX - 4, y: -4)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(.rect)
        .help(hovered.flatMap { data.bars.indices.contains($0) ? data.tooltip(of: data.bars[$0]) : nil } ?? "")
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): hovered = bar(at: location)
            case .ended: hovered = nil
            }
        }
        .onTapGesture { location in
            if let index = bar(at: location), data.manageable.contains(data.bars[index].key) {
                onSelect(data.bars[index].key)
            }
        }
        .contextMenu { menu }
        .confirmationDialog(
            Text("Delete this entry?"),
            isPresented: Binding {
                deleting != nil
            } set: {
                if !$0 { deleting = nil }
            },
            titleVisibility: .visible, presenting: deleting
        ) { bar in
            Button("Delete", role: .destructive) { onDelete(bar) }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: { bar in
            Text(verbatim: data.deleteMessage(bar))
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Day timeline"))
        .accessibilityValue(Text(verbatim: accessibilityValue))
        .accessibilityAddTraits(.isImage)
        .accessibilityActions {
            ForEach(data.bars.indices.filter { data.isDeletable(data.bars[$0]) }, id: \.self) { index in
                Button("Delete \(data.entryName(data.bars[index]))…") { deleting = data.bars[index] }
            }
        }
    }

    /// The entry, then Show in Manage Activities and Delete…, for the bar the pointer snapped to.
    @ViewBuilder private var menu: some View {
        if let hovered, data.bars.indices.contains(hovered) {
            let bar = data.bars[hovered]
            Text(verbatim: data.entryName(bar))
            if data.manageable.contains(bar.key) {
                Button("Show in Manage Activities") { onSelect(bar.key) }
            }
            if data.isDeletable(bar) {
                Button("Delete…") { deleting = bar }
            }
        }
    }

    /// The bar under the pointer or the nearest one within the snap radius, on the track only.
    private func bar(at location: CGPoint) -> Int? {
        guard width > 0, location.y <= Self.barHeight + Self.snapRadius else { return nil }
        let spans = data.bars.map { ($0.start * width)...($0.end * width) }
        return DayTimeline.nearest(to: location.x, in: spans, radius: Self.snapRadius)
    }

    /// "8:30 to 10:00 Internal, 10:00 to 12:15 Acme, 12:15 to 13:00 Break"
    private var accessibilityValue: String {
        data.lanes.map { lane in
            let name =
                switch lane.key {
                case .onBreak: String(localized: "Break")
                case .work(let customerId): DashboardData.name(of: customerId.flatMap { data.customers[$0] })
                }
            return DashboardData.spanLabel(lane.interval, name)
        }
        .formatted(.list(type: .and, width: .narrow))
    }

    static func hatch(_ path: Path, in rect: CGRect, context: GraphicsContext) {
        var context = context
        context.clip(to: path)
        context.fill(path, with: .color(Color(nsColor: .quinaryLabelColor)))
        var stripes = Path()
        for x in stride(from: rect.minX - rect.height, to: rect.maxX, by: 5) {
            stripes.move(to: CGPoint(x: x, y: rect.maxY))
            stripes.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
        }
        context.stroke(stripes, with: .color(Color(nsColor: .tertiaryLabelColor)), lineWidth: 1.5)
        context.contrastEdge(path, contrast: context.environment.colorSchemeContrast)
    }
}

/// Legend square in the customer color.
struct CustomerSwatch: View {
    let customer: Customer?

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(DashboardData.color(of: customer))
            .frame(width: 8, height: 8)
    }
}

/// Legend square for breaks, hatched like the timeline.
struct BreakSwatch: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            TimelineChart.hatch(Path(roundedRect: rect, cornerRadius: 2), in: rect, context: context)
        }
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
    }
}
