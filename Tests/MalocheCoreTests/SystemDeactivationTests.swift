import Foundation
import Testing

@testable import MalocheCore

@Suite struct SystemDeactivationTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func aResignRightBeforeOrAfterTheCauseCounts() {
        #expect(SystemDeactivation.caused(by: now, resignedAt: now.addingTimeInterval(0.001)))
        #expect(SystemDeactivation.caused(by: now, resignedAt: now.addingTimeInterval(-0.06)))
    }

    @Test func aLaterOrUnrelatedResignDoesNot() {
        #expect(!SystemDeactivation.caused(by: now, resignedAt: now.addingTimeInterval(2)))
        #expect(!SystemDeactivation.caused(by: nil, resignedAt: now))
        #expect(!SystemDeactivation.caused(by: now, resignedAt: nil))
    }
}
