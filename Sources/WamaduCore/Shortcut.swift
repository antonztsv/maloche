/// A global key combination: a virtual key code (`kVK_*`) and modifiers.
public struct Shortcut: Codable, Hashable, Sendable {
    /// Raw values are the Carbon modifier bits (`cmdKey`, `shiftKey`, `optionKey`, `controlKey`).
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 8)
        public static let shift = Modifiers(rawValue: 1 << 9)
        public static let option = Modifiers(rawValue: 1 << 11)
        public static let control = Modifiers(rawValue: 1 << 12)
    }

    public var keyCode: UInt32
    public var modifiers: Modifiers

    public init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Global shortcuts always include Command or Control, and only keys with a display name.
    public var isValid: Bool {
        !modifiers.isDisjoint(with: [.command, .control]) && Self.keyNames[keyCode] != nil
    }

    public var carbonModifiers: UInt32 { modifiers.rawValue }

    /// Modifiers in the order macOS shows them (Control, Option, Shift, Command), then the key, e.g. "⌃⌥⌘C".
    public var displayString: String {
        let symbols: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + (Self.keyNames[keyCode] ?? "")
    }

    // shortcut: fixed US key names, translate with UCKeyTranslate for the active layout once shortcuts are recordable
    static let keyNames: [UInt32: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C",
        0x09: "V", 0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y", 0x11: "T", 0x1F: "O",
        0x20: "U", 0x22: "I", 0x23: "P", 0x25: "L", 0x26: "J", 0x28: "K", 0x2D: "N", 0x2E: "M",
        0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5", 0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9",
        0x1D: "0",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
    ]
}

public enum ShortcutAction: String, CaseIterable, Codable, Sendable {
    case openCheckIn, toggleBreak, openDashboard

    /// Control, Option and Command together, since Option-Command-D toggles the Dock.
    public var defaultShortcut: Shortcut {
        let keyCode: UInt32 =
            switch self {
            case .openCheckIn: 0x08
            case .toggleBreak: 0x0B
            case .openDashboard: 0x02
            }
        return Shortcut(keyCode: keyCode, modifiers: [.control, .option, .command])
    }
}
