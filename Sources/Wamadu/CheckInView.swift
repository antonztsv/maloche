import SwiftUI

struct CheckInView: View {
    var onLog: (String) -> Void
    @State private var activity = "Code Review"
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("What are you working on?")
                    .font(.title3.weight(.semibold))
                Text("Since 10:15, 15 minutes")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 4)
            TextField("Activity", text: $activity)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit { onLog(activity) }
            HStack {
                Spacer()
                Button("Break") { onLog("Break") }
                Button("Log") { onLog(activity) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
        .padding(12)
        .padding(.top, 4)
        .frame(width: 380)
        .task { fieldFocused = true }
    }
}
