import AppKit
import MalocheCore
import SwiftUI

/// The day as blocks in customer colors with breaks hatched on a track, above an axis of full hours; each block shows
/// what it was and how long as a tooltip.
struct TimelineChart: View {
    var data: DashboardData
    var timeline: DayTimeline
    /// The activity of the clicked block.
    var onSelect: (Int64) -> Void = { _ in }
    @State private var frame = CGRect.zero

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
            GeometryReader { proxy in
                ForEach(data.bars.indices, id: \.self) { index in
                    let bar = data.bars[index]
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: max((bar.end - bar.start) * proxy.size.width, 1), height: Self.barHeight)
                        .offset(x: bar.start * proxy.size.width)
                        .help(data.tooltip(of: bar))
                }
            }
        }
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: {
            frame = $0
        }
        .onTapGesture(coordinateSpace: .global, perform: select)
        .accessibilityElement()
        .accessibilityLabel(Text("Day timeline"))
        .accessibilityValue(Text(verbatim: accessibilityValue))
        .accessibilityAddTraits(.isImage)
    }

    private func select(at location: CGPoint) {
        guard frame.width > 0, location.y - frame.minY <= Self.barHeight else { return }
        let x = (location.x - frame.minX) / frame.width
        if let bar = data.bars.first(where: { $0.start <= x && x <= $0.end && data.manageable.contains($0.key) }) {
            onSelect(bar.key)
        }
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
