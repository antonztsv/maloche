import Foundation
import Testing

@testable import MalocheCore

@Suite struct ClockTests {
    @Test func systemClockReturnsCurrentTime() {
        let before = Date()
        let now = SystemWallClock().now
        #expect(now >= before)
        #expect(now <= Date())
    }
}
