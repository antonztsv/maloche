import Testing

@testable import MalocheCore

@Suite struct UpdatesTests {
    private let key = String(repeating: "A", count: 43) + "="
    private let feed = "http://localhost:8000/appcast.xml"

    @Test func runsWithAFeedAndAKey() {
        #expect(Updates.isConfigured(info: ["SUFeedURL": feed, "SUPublicEDKey": key]))
    }

    @Test func staysOffWithoutAFeedOrAKey() {
        #expect(!Updates.isConfigured(info: [:]))
        #expect(!Updates.isConfigured(info: ["SUPublicEDKey": key]))
        #expect(!Updates.isConfigured(info: ["SUFeedURL": feed]))
    }

    @Test func staysOffWithEmptyOrUnusableValues() {
        #expect(!Updates.isConfigured(info: ["SUFeedURL": "", "SUPublicEDKey": key]))
        #expect(!Updates.isConfigured(info: ["SUFeedURL": feed, "SUPublicEDKey": "  \n"]))
        #expect(!Updates.isConfigured(info: ["SUFeedURL": "appcast.xml", "SUPublicEDKey": key]))
        #expect(!Updates.isConfigured(info: ["SUFeedURL": 42, "SUPublicEDKey": key]))
    }
}
