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
                    TextField("Customer", text: $draft.customer, prompt: Text(verbatim: ""))
                        .textFieldStyle(.plain)
                        .focused($focus, equals: .customer)
                        .onSubmit(submit)
                        .onKeyPress(.escape) {
                            onCancel()
                            return .handled
                        }
                    Menu {
                        ForEach(customers) { customer in
                            Button(customer.name) { draft.customer = customer.name }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .disabled(customers.isEmpty)
                    .accessibilityLabel(String(localized: "Customers"))
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
