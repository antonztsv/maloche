import MalocheCore
import SwiftUI

/// Work per day as bars stacked by customer from a zero baseline, the day's total above and the weekday below.
struct WeekChart: View {
    var data: DashboardData

    private static let plotHeight: CGFloat = 130

    var body: some View {
        let summary = data.summary
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(summary.days, id: \.interval.start) { day in
                VStack(spacing: 4) {
                    if day.work > 0 {
                        Text(duration: day.work)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        VStack(spacing: 2) {
                            ForEach(summary.stack(of: day).reversed(), id: \.customer?.id) { part in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(DashboardData.color(of: part.customer))
                                    .frame(height: height(of: part, in: day))
                            }
                        }
                    }
                    Text(day.interval.start, format: .dateTime.weekday(.abbreviated))
                        .font(.subheadline)
                        .foregroundStyle(day.work > 0 ? .secondary : .tertiary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(day.interval.start, format: .dateTime.weekday(.wide)))
                .accessibilityValue(spoken(day))
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .frame(height: Self.plotHeight + 40, alignment: .bottom)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Work per day"))
    }

    /// The part's share of the longest day, less the 2 pt gap below it.
    private func height(of part: CustomerWork, in day: DaySummary) -> CGFloat {
        max(data.summary.share(of: day) * part.duration / day.work * Self.plotHeight - 2, 1)
    }

    /// "8 hours, Acme 4 hours 30 minutes, Northwind 2 hours, Internal 1 hour 30 minutes"
    private func spoken(_ day: DaySummary) -> String {
        guard day.work > 0 else { return "" }
        let parts = data.summary.stack(of: day).map { part in
            String(
                localized: "\(DashboardData.name(of: part.customer)) \(DashboardData.spoken(part.duration))",
                comment: "A customer and its work, for VoiceOver")
        }
        return ([DashboardData.spoken(day.work)] + parts).formatted(.list(type: .and, width: .narrow))
    }
}

/// The month as a calendar from the first weekday, each day with its work on an accent fill growing with it.
struct MonthGrid: View {
    var data: DashboardData
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            GridRow {
                ForEach(data.calendar.orderedShortWeekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }
            ForEach(Array(data.summary.weeks(calendar: data.calendar).enumerated()), id: \.offset) { _, week in
                GridRow {
                    ForEach(0..<7, id: \.self) { index in
                        if let day = week[index] {
                            cell(day)
                        } else {
                            Color.clear
                                .frame(height: 38)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Work per day"))
    }

    private func cell(_ day: DaySummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(day.interval.start, format: .dateTime.day())
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if day.work > 0 {
                Text(duration: day.work)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38, alignment: .leading)
        .background(
            Color.accentColor.opacity(day.work > 0 ? 0.1 + 0.3 * data.summary.share(of: day) : 0),
            in: .rect(cornerRadius: 6)
        )
        .contrastEdge(cornerRadius: 6, contrast: contrast)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(day.interval.start, format: .dateTime.month(.wide).day()))
        .accessibilityValue(day.work > 0 ? DashboardData.spoken(day.work) : "")
        .accessibilityAddTraits(.isStaticText)
    }
}
