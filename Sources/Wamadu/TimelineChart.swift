import AppKit
import SwiftUI
import WamaduCore

/// The day as blocks in customer colors with breaks hatched on a track, above an axis labelled every second hour.
struct TimelineChart: View {
    var data: DashboardData
    var timeline: DayTimeline
    /// A block was clicked, with its frame in the global coordinate space.
    var onEdit: (Int64, CGRect) -> Void = { _, _ in }
    @State private var frame = CGRect.zero

    private static let barHeight: CGFloat = 24
    private static let axisTop: CGFloat = barHeight + 4

    var body: some View {
        let ticks = timeline.hourTicks(calendar: data.calendar)
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
            for tick in ticks {
                let label = context.resolve(
                    Text(tick, format: DashboardData.time).font(.caption).monospacedDigit()
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor)))
                let half = label.measure(in: size).width / 2
                let x = min(max(timeline.fraction(of: tick) * size.width, half), size.width - half)
                context.draw(label, at: CGPoint(x: x, y: Self.axisTop), anchor: .top)
            }
        }
        .frame(height: Self.axisTop + 14)
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: {
            frame = $0
        }
        .onTapGesture(coordinateSpace: .global, perform: edit)
        .accessibilityElement()
        .accessibilityLabel(Text("Day timeline"))
        .accessibilityValue(Text(verbatim: accessibilityValue))
        .accessibilityAddTraits(.isImage)
    }

    private func edit(at location: CGPoint) {
        guard frame.width > 0, location.y - frame.minY <= Self.barHeight else { return }
        let x = (location.x - frame.minX) / frame.width
        guard let bar = data.bars.first(where: { $0.start <= x && x <= $0.end && data.editable.contains($0.key) })
        else { return }
        onEdit(
            bar.key,
            CGRect(
                x: frame.minX + bar.start * frame.width, y: frame.minY, width: (bar.end - bar.start) * frame.width,
                height: Self.barHeight))
    }

    /// "8:30 to 10:00 Internal, 10:00 to 12:15 Acme, 12:15 to 13:00 Break"
    private var accessibilityValue: String {
        data.lanes.map { lane in
            let name =
                switch lane.key {
                case .onBreak: String(localized: "Break")
                case .work(let customerId): DashboardData.name(of: customerId.flatMap { data.customers[$0] })
                }
            let span = String(
                localized:
                    "\(lane.interval.start, format: DashboardData.time) to \(lane.interval.end, format: DashboardData.time)"
            )
            return String(localized: "\(span) \(name)", comment: "A time span and what it was spent on, for VoiceOver")
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
