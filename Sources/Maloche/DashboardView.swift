import AppKit
import MalocheCore
import SwiftUI

/// The day, week or month in the panel: period switcher, totals, chart, the list by customer, and the Now row.
struct DashboardView: View {
    var data: DashboardData
    var moreActions: MoreActionsMenu
    /// Previous or next period, or another period kind from the switcher.
    var onShowPeriod: (Period) -> Void
    /// Switches the panel to the check-in, from the Now row and from Check In Now.
    var onCheckIn: () -> Void
    var onKeepTracking: () -> Void
    /// A row or block was clicked, with its frame in the global coordinate space.
    var onEdit: (Int64, CGRect) -> Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            periodPicker
            if data.period.kind == .day, let timeline = data.timeline, let day = data.day {
                totals(day)
                TimelineChart(data: data, timeline: timeline, onEdit: onEdit)
                    .padding(.horizontal, 4)
                legend
                Divider()
                    .padding(.horizontal, 4)
                DashboardList(data: data, onEdit: onEdit)
            } else if data.period.kind != .day, data.summary.work > 0 || data.summary.breaks > 0 {
                periodTotals
                if data.period.kind == .week { WeekChart(data: data) } else { MonthGrid(data: data) }
                Divider()
                    .padding(.horizontal, 4)
                customerTotals
            } else {
                emptyPeriod
            }
            nowRow
        }
        .padding(12)
        .frame(width: 380)
    }

    private var header: some View {
        HStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                let title = title
                if let relative = title.relative {
                    relative
                        .font(.title3.weight(.semibold))
                    Text(title.date)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text(title.date)
                        .font(.title3.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            let paging = pagingLabels
            iconButton("chevron.left", paging.previous, key: .leftArrow) {
                onShowPeriod(data.period.previous(calendar: data.calendar))
            }
            iconButton("chevron.right", paging.next, key: .rightArrow, enabled: !data.isCurrent) {
                onShowPeriod(data.period.next(calendar: data.calendar))
            }
            moreActions
        }
        .padding(.leading, 4)
        .padding(.top, 2)
    }

    /// "Today" or "This week" beside the date, otherwise the date alone.
    private var title: (relative: Text?, date: String) {
        let start = data.period.interval.start
        switch data.period.kind {
        case .day:
            return (data.isCurrent ? Text("Today") : nil, start.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        case .week:
            let last = data.summary.days.last?.interval.start ?? start
            let range = Self.weekRange(from: start, to: last, calendar: data.calendar)
            return (data.isCurrent ? Text("This week") : data.isPrevious ? Text("Last week") : nil, range)
        case .month:
            return (nil, start.formatted(.dateTime.month(.wide).year()))
        }
    }

    /// "November 2 to 8" or "2. to 8. November" as the locale orders day and month, across months both in full.
    static func weekRange(from start: Date, to last: Date, calendar: Calendar, locale: Locale = .current) -> String {
        let monthDay = Date.FormatStyle.dateTime.month(.wide).day().locale(locale)
        let pattern = DateFormatter.dateFormat(fromTemplate: "MMMMd", options: 0, locale: locale) ?? "MMMM d"
        guard calendar.isDate(start, equalTo: last, toGranularity: .month),
            let dayIndex = pattern.firstIndex(of: "d"), let monthIndex = pattern.firstIndex(of: "M")
        else { return String(localized: "\(start.formatted(monthDay)) to \(last.formatted(monthDay))") }
        let day = DateFormatter()
        day.locale = locale
        // the day as the locale writes it before the month, e.g. "2." in German
        day.dateFormat = dayIndex < monthIndex ? pattern[..<monthIndex].trimmingCharacters(in: .whitespaces) : "d"
        return dayIndex < monthIndex
            ? String(localized: "\(day.string(from: start)) to \(last.formatted(monthDay))")
            : String(localized: "\(start.formatted(monthDay)) to \(day.string(from: last))")
    }

    private var pagingLabels: (previous: Text, next: Text) {
        switch data.period.kind {
        case .day: (Text("Previous day"), Text("Next day"))
        case .week: (Text("Previous week"), Text("Next week"))
        case .month: (Text("Previous month"), Text("Next month"))
        }
    }

    private func iconButton(
        _ symbol: String, _ label: Text, key: KeyEquivalent, enabled: Bool = true, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .keyboardShortcut(key, modifiers: .command)
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

    private var offersKeepTracking: Bool { data.current == .off || data.current == .doneForToday }

    private func keepTrackingRow(_ message: Text) -> some View {
        HStack {
            message
                .foregroundStyle(.secondary)
            Spacer()
            Button("Keep tracking", action: onKeepTracking)
                .keyboardRow(onKeepTracking)
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
        .keyboardRow(onCheckIn)
        .accessibilityHint(Text("Change activity"))
    }

    private var periodPicker: some View {
        Picker(
            "Period",
            selection: Binding(get: { data.period.kind }, set: showPeriod)
        ) {
            Text("Day").tag(PeriodKind.day)
            Text("Week").tag(PeriodKind.week)
            Text("Month").tag(PeriodKind.month)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .buttonSizing(.flexible)
        .keyCommand("1") { showPeriod(.day) }
        .keyCommand("2") { showPeriod(.week) }
        .keyCommand("3") { showPeriod(.month) }
    }

    private func showPeriod(_ kind: PeriodKind) {
        onShowPeriod(data.period.switched(to: kind, now: data.now, calendar: data.calendar))
    }

    private func totals(_ day: DaySummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            stat(Text("Work"), alignment: .leading) {
                Text(duration: day.work)
                    .font(.title2.weight(.semibold))
            }
            if day.breaks > 0 {
                stat(Text("Break"), alignment: .leading) {
                    Text(duration: day.breaks)
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

    /// Week: work, break and the average per day with work. Month: work and the days with work.
    private var periodTotals: some View {
        let summary = data.summary
        return HStack(alignment: .firstTextBaseline, spacing: 16) {
            stat(Text("Work"), alignment: .leading) {
                Text(duration: summary.work)
                    .font(.title2.weight(.semibold))
            }
            if data.period.kind == .week, summary.breaks > 0 {
                stat(Text("Break"), alignment: .leading) {
                    Text(duration: summary.breaks)
                        .font(.title2.weight(.semibold))
                }
            }
            Spacer(minLength: 0)
            if data.period.kind == .week {
                stat(Text("Per day"), alignment: .trailing) {
                    Text(duration: summary.averageWorkPerDay)
                        .font(.title2.weight(.semibold))
                }
            } else {
                stat(Text("Days"), alignment: .trailing) {
                    Text(summary.daysWithWork, format: .number)
                        .font(.title2.weight(.semibold))
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private var customerTotals: some View {
        VStack(spacing: 0) {
            ForEach(data.summary.customers, id: \.customer?.id) { total in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DashboardData.color(of: total.customer))
                        .frame(width: 8, height: 8)
                    Text(DashboardData.name(of: total.customer))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(duration: total.duration)
                        .monospacedDigit()
                }
                .frame(height: 28)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 4)
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

    private var emptyPeriod: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            switch (data.period.kind, data.isCurrent) {
            case (.day, true):
                Text("A fresh day")
                    .font(.body.weight(.semibold))
                Text("Your day shows up here as soon as you answer the first check-in.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
                Button("Check In Now", action: onCheckIn)
                    // NSApplication offers Return to the default button before the focused Keep tracking
                    .keyboardShortcut(offersKeepTracking ? nil : .defaultAction)
                    .controlSize(.large)
                    .padding(.top, 10)
            case (.day, false):
                Text("A quiet day")
                    .font(.body.weight(.semibold))
            case (.week, true):
                Text("A fresh week")
                    .font(.body.weight(.semibold))
            case (.week, false):
                Text("A quiet week")
                    .font(.body.weight(.semibold))
            case (.month, true):
                Text("A fresh month")
                    .font(.body.weight(.semibold))
            case (.month, false):
                Text("A quiet month")
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
    var onEdit: (Int64, CGRect) -> Void = { _, _ in }
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
            Text(duration: duration)
                .monospacedDigit()
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func row(_ total: ActivityTotal, customer: Customer?) -> some View {
        if let id = total.activity.id, data.editable.contains(id) {
            EditableRow {
                onEdit(id, $0)
            } label: {
                rowContent(total, customer: customer)
            }
        } else {
            rowContent(total, customer: customer)
        }
    }

    private func rowContent(_ total: ActivityTotal, customer: Customer?) -> some View {
        HStack(spacing: 8) {
            Text(total.activity.name)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            ProgressView(value: data.summary.work > 0 ? total.duration / data.summary.work : 0)
                .tint(DashboardData.color(of: customer))
                .frame(width: 56)
                .accessibilityHidden(true)
            Text(duration: total.duration)
                .monospacedDigit()
                .frame(minWidth: 36, alignment: .trailing)
        }
        .frame(height: 28)
        .accessibilityElement(children: .combine)
    }
}

/// A row that opens the entry editor beside itself.
private struct EditableRow<Label: View>: View {
    let onEdit: (CGRect) -> Void
    @ViewBuilder var label: Label
    @State private var frame = CGRect.zero

    var body: some View {
        Button {
            onEdit(frame)
        } label: {
            label.contentShape(.rect)
        }
        .buttonStyle(.plain)
        .keyboardRow { onEdit(frame) }
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: {
            frame = $0
        }
        .accessibilityHint(Text("Change times or activity"))
    }
}
