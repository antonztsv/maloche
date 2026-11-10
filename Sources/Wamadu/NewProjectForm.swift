import AppKit
import SwiftUI
import WamaduCore

struct ProjectDraft: Equatable {
    var name = ""
    var customer = ""
}

/// Name and customer of a new project, shown in place of the check-in field.
struct NewProjectForm: View {
    @Binding var draft: ProjectDraft
    let customers: [Customer]
    let onCancel: () -> Void
    let onCreate: () -> Void
    @FocusState private var focus: Field?

    private enum Field { case name, customer }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New project").font(.body.weight(.semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.subheadline).foregroundStyle(.secondary)
                TextField("Name", text: $draft.name, prompt: Text(verbatim: ""))
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .name)
                    .onSubmit(submit)
                    .onKeyPress(.escape) {
                        onCancel()
                        return .handled
                    }
                    .padding(.horizontal, 8)
                    .fieldBackground(focused: focus == .name)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Customer").font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if let match {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(nsColor: CustomerColor.nsColor(for: match)))
                            .frame(width: 8, height: 8)
                    }
                    CustomerField(text: $draft.customer, customers: customers, onSubmit: submit, onCancel: onCancel)
                        .focused($focus, equals: .customer)
                        // the combo box insets its text, this aligns it with the name field
                        .padding(.leading, -5)
                }
                .padding(.leading, 8)
                .padding(.trailing, 6)
                .fieldBackground(focused: focus == .customer)
                Text("Pick one or type a new customer name.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .task { focus = .name }
        Divider().padding(.horizontal, 4)
        HStack(spacing: 8) {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Create", action: onCreate)
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
        }
        .controlSize(.large)
    }

    private var canCreate: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Return in a field, the field takes it before the default button does.
    private func submit() {
        if canCreate { onCreate() }
    }

    private var match: Customer? {
        let name = draft.customer.trimmingCharacters(in: .whitespacesAndNewlines)
        return customers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

/// A combo box whose list shows the customers matching the typed words, free text names a new customer.
private struct CustomerField: NSViewRepresentable {
    @Binding var text: String
    let customers: [Customer]
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSComboBox {
        let field = NSComboBox()
        field.isBezeled = false
        field.isBordered = false
        field.isButtonBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        // fills the field's height, so the list opens at the field's bottom edge
        field.setContentHuggingPriority(.defaultLow, for: .vertical)
        field.font = .preferredFont(forTextStyle: .body)
        field.usesDataSource = true
        field.dataSource = context.coordinator
        field.delegate = context.coordinator
        field.stringValue = text
        field.setAccessibilityLabel(String(localized: "Customer"))
        return field
    }

    func updateNSView(_ field: NSComboBox, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    @MainActor final class Coordinator: NSObject, NSComboBoxDataSource, NSComboBoxDelegate {
        var parent: CustomerField
        private var typed = ""
        private var names: [String]

        init(_ parent: CustomerField) {
            self.parent = parent
            names = parent.customers.map(\.name)
        }

        private func show(matching query: String, in field: NSComboBox) {
            names = parent.customers.map(\.name).filter {
                query.isEmpty || Suggestions.startsWords(of: $0, query: query)
            }
            field.reloadData()
        }

        func numberOfItems(in comboBox: NSComboBox) -> Int { names.count }

        func comboBox(_ comboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? { names[index] }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSComboBox else { return }
            typed = field.stringValue
            parent.text = typed
            show(matching: typed, in: field)
            // the accessibility setter is the only public way to open the list
            field.cell?.setAccessibilityExpanded(!typed.isEmpty && !names.isEmpty)
        }

        /// Opened after a pick or with a preset name, the list offers every customer; typed text keeps its filter.
        func comboBoxWillPopUp(_ notification: Notification) {
            guard let field = notification.object as? NSComboBox, field.stringValue != typed else { return }
            show(matching: "", in: field)
        }

        /// Arrows, a click and `selectItem` all land here, the field shows the highlighted customer.
        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSComboBox, names.indices.contains(field.indexOfSelectedItem)
            else { return }
            parent.text = names[field.indexOfSelectedItem]
        }

        /// Return and Escape close an open list first, with the list closed they create or cancel.
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let field = control as? NSComboBox, let cell = field.cell else { return false }
            let open = cell.isAccessibilityExpanded()
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if open { cell.setAccessibilityExpanded(false) }
                if !open || field.indexOfSelectedItem < 0 { parent.onSubmit() }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                if open { cell.setAccessibilityExpanded(false) } else { parent.onCancel() }
                return true
            default:
                return false
            }
        }
    }
}
