import Foundation
import Testing

@testable import WamaduCore

@Suite struct IdleTransitionsTests {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func staysPresentBelowThreshold() {
        var idle = IdleTransitions(threshold: 120)
        #expect(idle.update(idleSeconds: 30, now: t0) == nil)
        #expect(idle.update(idleSeconds: 119, now: t0 + 89) == nil)
    }

    @Test func awayStartsAtLastInput() {
        var idle = IdleTransitions(threshold: 120)
        #expect(idle.update(idleSeconds: 125, now: t0) == .away(since: t0 - 125))
        #expect(idle.update(idleSeconds: 200, now: t0 + 75) == nil)
    }

    @Test func backOnFirstInputAfterAway() {
        var idle = IdleTransitions(threshold: 120)
        _ = idle.update(idleSeconds: 130, now: t0)
        #expect(idle.update(idleSeconds: 1, now: t0 + 600) == .back(at: t0 + 599))
        #expect(idle.update(idleSeconds: 5, now: t0 + 604) == nil)
    }
}
