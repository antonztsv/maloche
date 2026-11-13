import AppKit
import Testing

@testable import Maloche

/// The Dock icon is all or nothing: the setting alone decides, open windows do not.
@MainActor @Suite struct ActivationPolicyTests {
    @Test func theSettingAloneDecidesTheDockIcon() {
        #expect(NSWindow.activationPolicy(showInDock: true) == .regular)
        #expect(NSWindow.activationPolicy(showInDock: false) == .accessory)
    }
}
