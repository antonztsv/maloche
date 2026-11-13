import AppKit
import Testing

@testable import Maloche

/// The windows are built but never shown.
@MainActor @Suite struct WindowOrderTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private let settings = NSWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: true)
    private let manage = NSWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: true)

    @Test func windowsInFrontWhenTheIconClickDeactivatedTheAppComeBack() {
        var restored: [[NSWindow]] = []
        let keeper = WindowOrderKeeper { restored.append($0) }
        keeper.appResigned(frontWindows: [settings, manage], at: start)
        keeper.statusItemClicked(at: start.addingTimeInterval(0.2))
        #expect(restored == [[settings, manage]])

        keeper.statusItemClicked(at: start.addingTimeInterval(0.3))
        #expect(restored.count == 1, "restored once per deactivation")
    }

    @Test func theDeactivationMayArriveAfterTheClick() {
        var restored: [[NSWindow]] = []
        let keeper = WindowOrderKeeper { restored.append($0) }
        keeper.statusItemClicked(at: start)
        keeper.appResigned(frontWindows: [settings], at: start.addingTimeInterval(0.3))
        #expect(restored == [[settings]])
    }

    @Test func switchingToAnotherAppLaterLeavesTheWindowsWhereTheSystemPutsThem() {
        var restored: [[NSWindow]] = []
        let keeper = WindowOrderKeeper { restored.append($0) }
        keeper.statusItemClicked(at: start)
        keeper.appResigned(frontWindows: [settings], at: start.addingTimeInterval(2))
        keeper.appResigned(frontWindows: [], at: start.addingTimeInterval(10))
        keeper.statusItemClicked(at: start.addingTimeInterval(10.1))
        #expect(restored.isEmpty)
    }
}
