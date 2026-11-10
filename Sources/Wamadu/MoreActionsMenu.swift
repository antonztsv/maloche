import AppKit
import SwiftUI

/// The "…" menu of the panel.
struct MoreActionsMenu: View {
    var body: some View {
        // TODO: wire Done, Continue, Turn off, Manage Activities and Settings, only Quit acts yet
        Menu {
            Button("Done for today") {}.disabled(true)
            Menu("Continue without asking") {
                Button("Until I stop it") {}
                Divider()
                durations
            }
            .disabled(true)
            Menu("Turn off tracking") {
                Button("For this session") {}
                Divider()
                durations
            }
            .disabled(true)
            Divider()
            Button("Manage Activities…") {}.disabled(true)
            Button("Settings…") {}.keyboardShortcut(",").disabled(true)
            Divider()
            Button("Quit wamadu") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .foregroundStyle(.secondary)
        .fixedSize()
        .accessibilityLabel(String(localized: "More actions"))
    }

    @ViewBuilder private var durations: some View {
        Button("For 30 minutes") {}
        Button("For 1 hour") {}
        Button("For 2 hours") {}
        Button("For 3 hours") {}
        Button("For 4 hours") {}
    }
}
