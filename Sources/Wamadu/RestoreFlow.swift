import AppKit
import SwiftUI
import WamaduCore

/// Restore…: the open panel, then a confirmation that names the backup's date, or a note when the file is no backup.
@MainActor @Observable
final class RestoreFlow {
    var backup: RestorableBackup?
    var note: Text?

    /// From a click only, the open panel is modal.
    func choose(model: AppModel) {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Choose a wamadu backup to restore.")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.directoryURL = model.backupFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url, model: model)
    }

    /// Reads and checks the file, nothing changes before the confirmation.
    func open(_ url: URL, model: AppModel) {
        do {
            backup = try AppDatabase.readBackup(at: url, calendar: model.calendar)
        } catch {
            appLog.error("reading a backup failed: \(String(describing: error), privacy: .public)")
            note = Text("“\(url.lastPathComponent)” is not a wamadu backup. Your data stays as it is.")
        }
    }

    func restore(_ backup: RestorableBackup, model: AppModel) {
        self.backup = nil
        do {
            try model.restore(backup)
        } catch {
            appLog.error("restoring a backup failed: \(String(describing: error), privacy: .public)")
            note = Text("The restore did not go through, your data stays as it is.")
        }
    }
}

extension View {
    func restore(_ flow: RestoreFlow, model: AppModel) -> some View {
        confirmationDialog(
            flow.backup.map { Text("Restore the backup from \(BackupSettingsView.when($0.date))?") }
                ?? Text(verbatim: ""),
            isPresented: Binding {
                flow.backup != nil
            } set: {
                if !$0 { flow.backup = nil }
            },
            titleVisibility: .visible, presenting: flow.backup
        ) { backup in
            Button("Restore", role: .destructive) { flow.restore(backup, model: model) }
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: { _ in
            Text("Your current data is replaced with the backup. wamadu backs up your current data first.")
        }
        .alert(
            Text("Restore Backup"),
            isPresented: Binding {
                flow.note != nil
            } set: {
                if !$0 { flow.note = nil }
            },
            actions: {}, message: { flow.note })
    }
}
