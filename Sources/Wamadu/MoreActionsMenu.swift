import AppKit
import SwiftUI
import WamaduCore

/// The "…" menu of the check-in and the dashboard, a system menu.
struct MoreActionsMenu: View {
    let model: AppModel

    var body: some View {
        Menu {
            Button("Done for today", action: model.doneForToday)
            if model.mode == .continuing {
                Button("Stop continuing", action: model.stopContinuing)
            } else {
                Menu("Continue without asking") {
                    if let name = model.catalog.activity(model.activityToContinue)?.name {
                        Section("Keep logging \(name)") {
                            Button("Until I stop it") { model.continueWithoutAsking(for: nil) }
                            Divider()
                            durations { model.continueWithoutAsking(for: $0) }
                        }
                    }
                }
                .disabled(model.activityToContinue == nil)
            }
            if model.mode == .off {
                Button("Turn on tracking", action: model.turnOn)
            } else {
                Menu("Turn off tracking") {
                    Button("For this session") { model.turnOff(for: nil) }
                    Divider()
                    durations { model.turnOff(for: $0) }
                }
            }
            Divider()
            Button("Manage Activities…", action: model.openManageActivities)
            Button("Settings…", action: model.openSettings).keyboardShortcut(",")
            Divider()
            Button("Quit wamadu") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .foregroundStyle(.secondary)
        .fixedSize()
        .help(Text("More actions"))
        .accessibilityLabel(String(localized: "More actions"))
    }

    @ViewBuilder private func durations(_ action: @escaping (TimeInterval) -> Void) -> some View {
        Button("For 30 minutes") { action(30 * 60) }
        Button("For 1 hour") { action(3600) }
        Button("For 2 hours") { action(2 * 3600) }
        Button("For 3 hours") { action(3 * 3600) }
        Button("For 4 hours") { action(4 * 3600) }
    }
}
