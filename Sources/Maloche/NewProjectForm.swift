import AppKit
import MalocheCore
import SwiftUI

struct ProjectDraft: Equatable {
    var name = ""
    var customer = ""
    /// A new customer without project, only the name is asked.
    var forCustomer = false
}

/// Name and customer of a new project, or the name of a new customer, shown in place of the check-in field.
struct NewProjectForm: View {
    @Binding var draft: ProjectDraft
    let customers: [Customer]
    let onCancel: () -> Void
    let onCreate: () -> Void
    @FocusState private var focus: Field?

    private enum Field { case name, customer }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            (draft.forCustomer ? Text("New customer") : Text("New project")).font(.body.weight(.semibold))
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
            if !draft.forCustomer { customerField }
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

    private var customerField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Customer").font(.subheadline).foregroundStyle(.secondary)
            // at the name's text, or after the color square and its 6 pt spacing
            CustomerField(
                text: $draft.customer, customers: customers, textStart: match == nil ? 8 : 22, onSubmit: submit,
                onCancel: onCancel
            )
            .focused($focus, equals: .customer)
            .padding(.leading, CustomerField.listOutset.leading)
            .padding(.trailing, CustomerField.listOutset.trailing)
            .overlay(alignment: .leading) {
                if let match {
                    CustomerSwatch(customer: match)
                        .padding(.leading, 8)
                }
            }
            .fieldBackground(focused: focus == .customer)
            Text("Pick one or type a new customer name.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
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
    /// Where the text starts, from the leading edge of the field.
    let textStart: CGFloat
    let onSubmit: () -> Void
    let onCancel: () -> Void

    /// AppKit opens the list this far outside the combo box's frame (measured, the same for every width).
    static let listOutset = (leading: 9.0, trailing: 8.0)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSComboBox {
        let field = ComboBox()
        field.isBezeled = false
        field.isBordered = false
        field.isButtonBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        // fills the field's height, so the list opens at the field's bottom edge
        field.setContentHuggingPriority(.defaultLow, for: .vertical)
        field.font = .preferredFont(forTextStyle: .body)
        field.usesDataSource = true
        // longer lists scroll
        field.numberOfVisibleItems = 8
        field.dataSource = context.coordinator
        field.delegate = context.coordinator
        field.stringValue = text
        field.cell?.setAccessibilityLabel(String(localized: "Customer"))
        return field
    }

    func updateNSView(_ field: NSComboBox, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        let start = textStart - Self.listOutset.leading
        guard let cell = field.cell as? Cell, cell.textStart != start else { return }
        cell.textStart = start
        field.needsDisplay = true
        // places the field editor again, at the new start
        if let editor = field.currentEditor() {
            let selection = editor.selectedRange
            cell.select(
                withFrame: field.bounds, in: field, editor: editor, delegate: field, start: selection.location,
                length: selection.length)
        }
    }

    private final class ComboBox: NSComboBox {
        override class var cellClass: AnyClass? {
            get { Cell.self }
            set {}
        }

        private var clickMonitor: Any?

        /// A click or Tab into the field shows the list before anything is typed.
        override func becomeFirstResponder() -> Bool {
            guard super.becomeFirstResponder() else { return false }
            openList()
            // while editing, clicks reach the field editor and not this field, a closed list opens again on each one
            clickMonitor =
                clickMonitor
                ?? NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                    if let self, event.window == self.window,
                        self.bounds.contains(self.convert(event.locationInWindow, from: nil))
                    {
                        self.openList()
                    }
                    return event
                }
            return true
        }

        override func textDidEndEditing(_ notification: Notification) {
            super.textDidEndEditing(notification)
            stopWatchingClicks()
        }

        /// The panel can close while the field is still being edited.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { stopWatchingClicks() }
        }

        private func stopWatchingClicks() {
            if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
            clickMonitor = nil
        }

        /// After the field editor took over; the accessibility setter is the only public way to open the list.
        private func openList() {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.currentEditor() != nil, self.numberOfItems > 0,
                    self.cell?.isAccessibilityExpanded() == false
                else { return }
                self.cell?.setAccessibilityExpanded(true)
            }
        }

        // zero horizontally, so the padding around the field places the frame and with it the list
        override var alignmentRectInsets: NSEdgeInsets {
            let insets = super.alignmentRectInsets
            return NSEdgeInsets(top: insets.top, left: 0, bottom: insets.bottom, right: 0)
        }
    }

    /// Moves the text, drawn and edited, to `textStart` from the frame's leading edge.
    private final class Cell: NSComboBoxCell {
        var textStart: CGFloat = 0

        override func titleRect(forBounds rect: NSRect) -> NSRect {
            var title = super.titleRect(forBounds: rect)
            // the cell and the field editor pad the text by 2 pt
            let minX = rect.minX + textStart - 2
            title.size.width = title.maxX - minX
            title.origin.x = minX
            return title
        }

        override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
            super.drawInterior(withFrame: shifted(cellFrame), in: controlView)
        }

        override func edit(
            withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?
        ) {
            super.edit(withFrame: shifted(rect), in: controlView, editor: textObj, delegate: delegate, event: event)
        }

        override func select(
            withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int,
            length selLength: Int
        ) {
            super.select(
                withFrame: shifted(rect), in: controlView, editor: textObj, delegate: delegate, start: selStart,
                length: selLength)
        }

        /// The cell draws the text and places the field editor at the default title rect, this moves both.
        private func shifted(_ rect: NSRect) -> NSRect {
            let shift = titleRect(forBounds: rect).minX - super.titleRect(forBounds: rect).minX
            return NSRect(x: rect.minX + shift, y: rect.minY, width: rect.width - shift, height: rect.height)
        }
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
