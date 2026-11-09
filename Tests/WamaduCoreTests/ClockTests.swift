import Foundation
import Testing

@testable import WamaduCore

@Suite struct ClockTests {
    @Test func systemClockReturnsCurrentTime() {
        let before = Date()
        let now = SystemClock().now
        #expect(now >= before)
        #expect(now <= Date())
    }
}
