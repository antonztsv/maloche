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

    @Test func acceptsSecureFeedsAndLocalhostOnly() {
        let accepted = [
            "https://example.com/appcast.xml", "http://localhost:8000/appcast.xml", "http://127.0.0.1:8000/a.xml",
        ]
        for url in accepted {
            #expect(Updates.isConfigured(info: ["SUFeedURL": url, "SUPublicEDKey": key]))
        }
        for url in ["http://example.com/appcast.xml", "ftp://example.com/a.xml", "file:///tmp/a.xml"] {
            #expect(!Updates.isConfigured(info: ["SUFeedURL": url, "SUPublicEDKey": key]))
        }
    }
}
