import AppKit
import SwiftUI
import WamaduCore

/// The day as blocks in customer colors with breaks hatched, above an axis labelled every second hour.
struct TimelineChart: View {
    var data: DashboardData
    var timeline: DayTimeline
    var showsAxis = true

    private static let barHeight: CGFloat = 24
    private static let axisTop: CGFloat = barHeight + 4

    var body: some View {
        let ticks = showsAxis ? timeline.hourTicks(calendar: data.calendar) : []
        Canvas { context, size in
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
        .frame(height: showsAxis ? Self.axisTop + 14 : Self.barHeight)
        .accessibilityElement()
        .accessibilityLabel(Text("Day timeline"))
        .accessibilityValue(Text(verbatim: accessibilityValue))
        .accessibilityAddTraits(.isImage)
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
