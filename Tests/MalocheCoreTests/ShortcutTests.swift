import Carbon.HIToolbox
import Foundation
import Testing

@testable import MalocheCore

@Suite struct ShortcutTests {
    private let keyC = UInt32(kVK_ANSI_C)

    @Test func needsCommandOrControl() {
        #expect(Shortcut(keyCode: keyC, modifiers: [.command]).isValid)
        #expect(Shortcut(keyCode: keyC, modifiers: [.control]).isValid)
        #expect(Shortcut(keyCode: keyC, modifiers: [.control, .option, .shift, .command]).isValid)
        #expect(!Shortcut(keyCode: keyC, modifiers: [.option, .shift]).isValid)
        #expect(!Shortcut(keyCode: keyC, modifiers: []).isValid)
    }

    @Test func keyWithoutDisplayNameIsInvalid() {
        #expect(!Shortcut(keyCode: UInt32(kVK_ANSI_KeypadEnter), modifiers: [.command]).isValid)
    }

    @Test func carbonModifiersMatchCarbonConstants() {
        #expect(Shortcut(keyCode: keyC, modifiers: [.command]).carbonModifiers == UInt32(cmdKey))
        #expect(Shortcut(keyCode: keyC, modifiers: [.control]).carbonModifiers == UInt32(controlKey))
        #expect(Shortcut(keyCode: keyC, modifiers: [.option]).carbonModifiers == UInt32(optionKey))
        #expect(Shortcut(keyCode: keyC, modifiers: [.shift]).carbonModifiers == UInt32(shiftKey))
        #expect(
            Shortcut(keyCode: keyC, modifiers: [.control, .option, .shift, .command]).carbonModifiers
                == UInt32(cmdKey | controlKey | optionKey | shiftKey))
    }

    @Test func displayStringOrdersModifiersLikeMacOS() {
        #expect(Shortcut(keyCode: keyC, modifiers: [.command, .shift, .option, .control]).displayString == "⌃⌥⇧⌘C")
        #expect(Shortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: [.command, .control]).displayString == "⌃⌘A")
        #expect(Shortcut(keyCode: UInt32(kVK_ANSI_Z), modifiers: [.command]).displayString == "⌘Z")
        #expect(Shortcut(keyCode: UInt32(kVK_ANSI_0), modifiers: [.command]).displayString == "⌘0")
        #expect(Shortcut(keyCode: UInt32(kVK_ANSI_9), modifiers: [.command]).displayString == "⌘9")
        #expect(Shortcut(keyCode: UInt32(kVK_F1), modifiers: [.control]).displayString == "⌃F1")
        #expect(Shortcut(keyCode: UInt32(kVK_F12), modifiers: [.option, .command]).displayString == "⌥⌘F12")
    }

    @Test func keyNamesMatchCarbonKeyCodes() {
        let letters = [
            kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_I,
            kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R,
            kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Y, kVK_ANSI_Z,
        ]
        let digits = [
            kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8,
            kVK_ANSI_9,
        ]
        let functionKeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
        ]
        var expected: [(Int, String)] = Array(zip(letters, "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)))
        expected += zip(digits, (0...9).map(String.init))
        expected += zip(functionKeys, (1...12).map { "F\($0)" })
        for (keyCode, name) in expected {
            #expect(Shortcut.keyNames[UInt32(keyCode)] == name)
        }
        #expect(Shortcut.keyNames.count == expected.count)
    }

    @Test func defaultsAvoidTheDockShortcut() {
        #expect(ShortcutAction.openCheckIn.defaultShortcut.displayString == "⌃⌥⌘C")
        #expect(ShortcutAction.toggleBreak.defaultShortcut.displayString == "⌃⌥⌘B")
        #expect(ShortcutAction.openDashboard.defaultShortcut.displayString == "⌃⌥⌘D")
        #expect(ShortcutAction.allCases.allSatisfy { $0.defaultShortcut.isValid })
    }

    @Test func codableRoundTrip() throws {
        let shortcut = Shortcut(keyCode: UInt32(kVK_F5), modifiers: [.control, .shift])
        let data = try JSONEncoder().encode(shortcut)
        #expect(try JSONDecoder().decode(Shortcut.self, from: data) == shortcut)
    }
}

@Suite struct ShortcutRecordingTests {
    private let defaults = ShortcutAction.defaultShortcuts

    private func press(
        _ keyCode: Int, _ modifiers: Shortcut.Modifiers, for action: ShortcutAction = .openCheckIn,
        in shortcuts: [ShortcutAction: Shortcut]? = nil
    ) -> ShortcutRecording {
        ShortcutRecording(
            keyCode: UInt32(keyCode), modifiers: modifiers, for: action, in: shortcuts ?? defaults)
    }

    @Test func takesAKeyWithCommandOrControl() {
        #expect(
            press(kVK_ANSI_K, [.control, .option]) == .record(Shortcut(keyCode: 0x28, modifiers: [.control, .option])))
        #expect(press(kVK_F5, [.command]) == .record(Shortcut(keyCode: 0x60, modifiers: [.command])))
    }

    @Test func refusesAKeyWithoutCommandOrControl() {
        for modifiers: Shortcut.Modifiers in [[], [.shift], [.option], [.option, .shift]] {
            #expect(press(kVK_ANSI_K, modifiers) == .refuse)
        }
    }

    @Test func refusesAKeyWithoutName() {
        #expect(press(kVK_ANSI_KeypadEnter, [.command]) == .refuse)
    }

    @Test func refusesTheKeysOfAnotherActionAndKeepsItsOwn() {
        #expect(press(kVK_ANSI_B, [.control, .option, .command]) == .refuse)
        #expect(
            press(kVK_ANSI_C, [.control, .option, .command]) == .record(ShortcutAction.openCheckIn.defaultShortcut))
        var cleared = defaults
        cleared[.toggleBreak] = nil
        #expect(
            press(kVK_ANSI_B, [.control, .option, .command], in: cleared)
                == .record(ShortcutAction.toggleBreak.defaultShortcut))
    }

    @Test func escapeCancelsAndDeleteClears() {
        #expect(press(kVK_Escape, []) == .cancel)
        #expect(press(kVK_Escape, [.command]) == .cancel)
        #expect(press(kVK_Delete, []) == .clear)
        #expect(press(kVK_ForwardDelete, []) == .clear)
    }

    @Test func defaultShortcutsCoverEveryAction() {
        #expect(defaults.count == ShortcutAction.allCases.count)
        #expect(ShortcutAction.allCases.allSatisfy { defaults[$0] == $0.defaultShortcut })
    }
}
