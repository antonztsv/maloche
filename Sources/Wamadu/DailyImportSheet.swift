import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WamaduCore

/// Import from Daily: the open panel, then the preview sheet, or a note when the files cannot be read.
@MainActor @Observable
final class DailyImportFlow {
    var preview: DailyImport?
    var note: Text?

    /// From a click only, the open panel is modal.
    func choose(model: AppModel) {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Choose the folder with activities.json and timesheet.json, or both files.")
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK else { return }
        open(panel.urls, model: model)
    }

    func open(_ urls: [URL], model: AppModel) {
        do {
            preview = try model.database.dailyImport(DailyExport(contentsOf: urls), calendar: model.calendar)
        } catch DailyExport.ReadError.unreadable(let file) {
            note = Text("“\(file.rawValue)” could not be read. Choose the files from the Daily export.")
        } catch {
            note = Text("Choose the folder from the Daily export with activities.json and timesheet.json.")
        }
    }
}

extension View {
    func dailyImport(_ flow: DailyImportFlow, model: AppModel) -> some View {
        sheet(
            isPresented: Binding {
                flow.preview != nil
            } set: {
                if !$0 { flow.preview = nil }
            }
        ) {
            if let preview = flow.preview {
                DailyImportView(preview: preview) { plan in try model.manage { try $0.importDaily(plan) } }
            }
        }
        .alert(
            Text("Import from Daily"),
            isPresented: Binding {
                flow.note != nil
            } set: {
                if !$0 { flow.note = nil }
            },
            actions: {}, message: { flow.note })
    }
}

/// Counts, the customers found in "x - y" names and the choice to shorten the names; nothing is written before Import.
struct DailyImportView: View {
    static let size = CGSize(width: 560, height: 520)

    @State var preview: DailyImport
    let commit: (DailyImport.Plan) throws -> Void
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import from Daily")
                    .font(.title3.weight(.semibold))
                Group {
                    summary
                    if preview.daysWithTime > 0 {
                        Text("Keeps your time on ^[\(preview.daysWithTime) day](inflect: true) as it is.")
                    }
                    if preview.skippedDays > 0 {
                        Text(
                            """
                            Skips ^[\(preview.skippedDays) day](inflect: true) without a start time \
                            or with more than 24 hours.
                            """)
                    }
                }
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding([.horizontal, .top], 20)
            Form {
                if !preview.prefixes.isEmpty {
                    Section {
                        ForEach($preview.prefixes, content: row)
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Customers in your activity names")
                            Text(
                                "Names like “Customer - Task” start with a customer. Pick the ones wamadu should create."
                            )
                            .font(.subheadline)
                            .fontWeight(.regular)
                            .foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        Toggle("Remove the customer part from activity names", isOn: $preview.removesPrefix)
                            .toggleStyle(.checkbox)
                    } footer: {
                        let kept = preview.keepingFullName.count
                        if kept > 0 {
                            Text(
                                """
                                Keeps the full name for ^[\(kept) activity](inflect: true) \
                                whose short name is already in use.
                                """
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            Group {
                if failed {
                    Text("The import did not go through, nothing changed.")
                } else {
                    Text(
                        """
                        Daily stores totals per day, not exact times. \
                        Imported days keep their totals, start and end of the day.
                        """)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            // in line with the section headers of the grouped form
            .padding(.horizontal, 30)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import", action: run)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var summary: Text {
        let activities = preview.activityCount
        let days = preview.dayCount
        guard let first = preview.firstDay, let last = preview.lastDay else {
            return Text("Found ^[\(activities) activity](inflect: true) and no days with time.")
        }
        let withYear = Date.FormatStyle.dateTime.month(.wide).day().year()
        guard first != last else {
            let day = first.formatted(withYear)
            return Text("Found ^[\(activities) activity](inflect: true) and ^[\(days) day](inflect: true), \(day).")
        }
        let sameYear = Calendar.current.isDate(first, equalTo: last, toGranularity: .year)
        let from = first.formatted(sameYear ? .dateTime.month(.wide).day() : withYear)
        let to = last.formatted(withYear)
        return Text(
            "Found ^[\(activities) activity](inflect: true) and ^[\(days) day](inflect: true), \(from) to \(to).")
    }

    private func row(_ prefix: Binding<DailyImport.Prefix>) -> some View {
        let text = prefix.wrappedValue.text
        return HStack(spacing: 10) {
            Toggle(isOn: prefix.isOn) {
                Text(verbatim: text)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .toggleStyle(.checkbox)
            .accessibilityLabel(Text("Create customer from \(text)"))
            .frame(width: 140, alignment: .leading)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(text: prefix.customerName) { Text("Customer name for \(text)") }
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .disabled(!prefix.wrappedValue.isOn)
            Text("^[\(prefix.wrappedValue.count) activity](inflect: true)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 90, alignment: .trailing)
        }
    }

    private func run() {
        do {
            try commit(preview.plan)
            dismiss()
        } catch {
            appLog.error("importing from Daily failed: \(String(describing: error), privacy: .public)")
            failed = true
        }
    }
}
