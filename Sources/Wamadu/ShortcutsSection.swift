import AppKit
import Carbon.HIToolbox
import SwiftUI
import WamaduCore

/// A click on a shortcut records the next keys: Escape cancels, Delete clears, the keys of another action are refused.
struct ShortcutsSection: View {
    let model: AppModel
    let onRecording: (Bool) -> Void
    @State private var recording: ShortcutAction?
    @State private var monitor: Any?
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        Section("Keyboard shortcuts") {
            ForEach(ShortcutAction.allCases, id: \.self) { action in
                LabeledContent(action.title) {
                    Button {
                        recording = recording == action ? nil : action
                    } label: {
                        Text(label(of: action))
                            .frame(minWidth: 72)
                    }
                    .tint(recording == action ? .accentColor : nil)
                    .help(Text("Click and press the new keys. Escape cancels, Delete clears the shortcut."))
                    .accessibilityLabel(action.title)
                    .accessibilityValue(label(of: action))
                }
            }
        }
        .onChange(of: recording) { _, action in record(action) }
        .onChange(of: appearsActive) { _, active in
            if !active { recording = nil }
        }
        .onDisappear {
            recording = nil
            record(nil)
        }
    }

    private func label(of action: ShortcutAction) -> String {
        if recording == action { return String(localized: "Type Shortcut") }
        return model.settings.shortcuts[action]?.localizedDisplayString ?? String(localized: "Record Shortcut")
    }

    private func record(_ action: ShortcutAction?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        onRecording(action != nil)
        guard let action else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let consumed = MainActor.assumeIsolated { handle(event, for: action) }
            return consumed ? nil : event
        }
    }

    /// False for keys of another window, they end the recording and reach that window.
    private func handle(_ event: NSEvent, for action: ShortcutAction) -> Bool {
        guard event.window?.identifier == SettingsWindowController.identifier else {
            recording = nil
            return false
        }
        var settings = model.settings
        switch ShortcutRecording(
            keyCode: UInt32(event.keyCode), modifiers: Shortcut.Modifiers(event.modifierFlags), for: action,
            in: settings.shortcuts)
        {
        case .cancel:
            recording = nil
        case .clear:
            settings.shortcuts[action] = nil
            model.update(settings)
            recording = nil
        case .record(let shortcut):
            settings.shortcuts[action] = shortcut
            model.update(settings)
            recording = nil
        case .refuse:
            NSSound.beep()
        }
        return true
    }
}

extension ShortcutAction {
    var title: String {
        switch self {
        case .openCheckIn: String(localized: "Open check-in")
        case .toggleBreak: String(localized: "Start break")
        case .openDashboard: String(localized: "Open dashboard")
        }
    }
}

extension Shortcut.Modifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        let pairs: [(NSEvent.ModifierFlags, Self)] = [
            (.control, .control), (.option, .option), (.shift, .shift), (.command, .command),
        ]
        self.init(pairs.filter { flags.contains($0.0) }.map(\.1))
    }
}

extension Shortcut {
    /// With the key as the active keyboard layout names it, e.g. "⌃⌥⌘Z" for the key right of T on a German keyboard.
    var localizedDisplayString: String {
        displayString(keyName: Self.layoutName(of: keyCode))
    }

    /// Nil for keys without a printable character, such as the function keys.
    private static func layoutName(of keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layout = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layout.withUnsafeBytes { bytes in
            UCKeyTranslate(
                bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress, UInt16(keyCode), UInt16(kUCKeyActionDisplay),
                0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, characters.count,
                &length, &characters)
        }
        let name = String(utf16CodeUnits: characters, count: length).uppercased()
        let printable = name.unicodeScalars.allSatisfy { $0.properties.isGraphemeBase || $0.properties.isAlphabetic }
        return status == noErr && !name.isEmpty && printable ? name : nil
    }
}
