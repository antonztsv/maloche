import AppKit
import SwiftUI
import WamaduCore

/// The day in the panel: period switcher, totals, timeline, the list by customer and project, and the Now row.
struct DashboardView: View {
    var data: DashboardData
    var moreActions: MoreActionsMenu
    /// Previous or next day, or another period kind from the switcher.
    var onShowPeriod: (Period) -> Void
    /// Switches the panel to the check-in, from the Now row and from Check In Now.
    var onCheckIn: () -> Void
    var onKeepTracking: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            periodPicker
            if let timeline = data.timeline, let day = data.day {
                totals(day)
                TimelineChart(data: data, timeline: timeline)
                    .padding(.horizontal, 4)
                legend
                Divider()
                    .padding(.horizontal, 4)
                DashboardList(data: data)
            } else {
                emptyDay
            }
            nowRow
        }
        .padding(12)
        .frame(width: 380)
    }

    private var header: some View {
        HStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                let date = data.period.interval.start.formatted(.dateTime.weekday(.wide).month(.wide).day())
                if data.isToday {
                    Text("Today")
                        .font(.title3.weight(.semibold))
                    Text(date)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text(date)
                        .font(.title3.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            iconButton("chevron.left", Text("Previous day")) {
                onShowPeriod(data.period.previous(calendar: data.calendar))
            }
            iconButton("chevron.right", Text("Next day"), enabled: !data.isToday) {
                onShowPeriod(data.period.next(calendar: data.calendar))
            }
            moreActions
        }
        .padding(.leading, 4)
        .padding(.top, 2)
    }

    private func iconButton(
        _ symbol: String, _ label: Text, enabled: Bool = true, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(enabled ? .secondary : .tertiary)
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }

    @ViewBuilder private var nowRow: some View {
        switch data.current {
        case .activity(let id):
            let customer = data.customer(of: id)
            nowButton(
                name: data.activities[id]?.name ?? "", customer: DashboardData.name(of: customer),
                swatch: Circle().fill(DashboardData.color(of: customer)).frame(width: 8, height: 8))
        case .onBreak:
            nowButton(name: String(localized: "Break"), customer: nil, swatch: BreakSwatch().clipShape(.circle))
        case .off: keepTrackingRow(Text("Tracking is off"))
        case .doneForToday: keepTrackingRow(Text("That’s it for today"))
        case .none: EmptyView()
        }
    }

    private func keepTrackingRow(_ message: Text) -> some View {
        HStack {
            message
                .foregroundStyle(.secondary)
            Spacer()
            Button("Keep tracking", action: onKeepTracking)
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 32)
        .background(Color(nsColor: .quaternarySystemFill), in: .rect(cornerRadius: 8))
    }

    private func nowButton(name: String, customer: String?, swatch: some View) -> some View {
        Button(action: onCheckIn) {
            HStack(spacing: 8) {
                Text("Now")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                swatch
                Text(name)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let customer {
                    Text(customer)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .frame(height: 32)
            .background(Color(nsColor: .quaternarySystemFill), in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Change activity"))
    }

    private var periodPicker: some View {
        Picker(
            "Period",
            selection: Binding(
                get: { data.period.kind },
                set: { kind in
                    // TODO: enable week and month once their views exist, the day layout cannot show them
                    guard kind == .day else { return }
                    onShowPeriod(Period(kind, containing: data.period.interval.start, calendar: data.calendar))
                })
        ) {
            Text("Day").tag(PeriodKind.day)
            Text("Week").tag(PeriodKind.week).selectionDisabled()
            Text("Month").tag(PeriodKind.month).selectionDisabled()
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .buttonSizing(.flexible)
    }

    private func totals(_ day: DaySummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            stat(Text("Work"), alignment: .leading) {
                Text(DashboardData.duration(day.work))
                    .font(.title2.weight(.semibold))
            }
            if day.breaks > 0 {
                stat(Text("Break"), alignment: .leading) {
                    Text(DashboardData.duration(day.breaks))
                        .font(.title2.weight(.semibold))
                }
            }
            Spacer(minLength: 0)
            if let start = day.start, let end = day.end {
                stat(Text("Workday"), alignment: .trailing) {
                    Text("\(start, format: DashboardData.time) to \(end, format: DashboardData.time)")
                        .font(.title2.weight(.semibold))
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private func stat(
        _ label: Text, alignment: HorizontalAlignment, @ViewBuilder value: () -> some View
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            label
                .font(.subheadline)
                .foregroundStyle(.secondary)
            value()
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { legendItems }
            VStack(alignment: .leading, spacing: 4) { legendItems }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    @ViewBuilder private var legendItems: some View {
        ForEach(data.summary.customers, id: \.customer?.id) { total in
            legendItem(DashboardData.name(of: total.customer)) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(DashboardData.color(of: total.customer))
                    .frame(width: 8, height: 8)
            }
        }
        if data.day?.breaks ?? 0 > 0 {
            legendItem(String(localized: "Break")) { BreakSwatch() }
        }
    }

    private func legendItem(_ name: String, @ViewBuilder swatch: () -> some View) -> some View {
        HStack(spacing: 5) {
            swatch()
            Text(name)
                .lineLimit(1)
        }
    }

    private var emptyDay: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            if data.isToday {
                Text("A fresh day")
                    .font(.body.weight(.semibold))
                Text("Your day shows up here as soon as you answer the first check-in.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
                Button("Check In Now", action: onCheckIn)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .padding(.top, 10)
            } else {
                Text("A quiet day")
                    .font(.body.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 36)
        .padding(.bottom, 32)
    }
}

/// Work by customer, then project, each activity with its share of the day as a bar.
struct DashboardList: View {
    var data: DashboardData
    @State private var collapsed: Set<Int64?> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(data.summary.customers, id: \.customer?.id) { total in
                DisclosureGroup(isExpanded: expanded(total.customer?.id)) {
                    VStack(alignment: .leading, spacing: 0) {
                        // activities without project first, below a project header they would read as part of it
                        let projects =
                            total.projects.filter { $0.project == nil } + total.projects.filter { $0.project != nil }
                        ForEach(projects, id: \.project?.id) { project in
                            if let name = project.project?.name {
                                subtotal(name, project.duration)
                                    .frame(height: 22)
                            }
                            ForEach(project.activities, id: \.activity.id) { row($0, customer: total.customer) }
                        }
                    }
                    .padding(.leading, 26)
                    .padding(.trailing, 4)
                } label: {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(DashboardData.color(of: total.customer))
                            .frame(width: 8, height: 8)
                        subtotal(DashboardData.name(of: total.customer), total.duration)
                            .fontWeight(.semibold)
                    }
                    .frame(height: 22)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func expanded(_ id: Int64?) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(id) },
            set: { isExpanded in
                if isExpanded { collapsed.remove(id) } else { collapsed.insert(id) }
            })
    }

    private func subtotal(_ name: String, _ duration: TimeInterval) -> some View {
        HStack {
            Text(name)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(DashboardData.duration(duration))
                .monospacedDigit()
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private func row(_ total: ActivityTotal, customer: Customer?) -> some View {
        HStack(spacing: 8) {
            Text(total.activity.name)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            ProgressView(value: data.summary.work > 0 ? total.duration / data.summary.work : 0)
                .tint(DashboardData.color(of: customer))
                .frame(width: 56)
                .accessibilityHidden(true)
            Text(DashboardData.duration(total.duration))
                .monospacedDigit()
                .frame(minWidth: 36, alignment: .trailing)
        }
        .frame(height: 28)
        .accessibilityElement(children: .combine)
    }
}
