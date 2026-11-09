import Testing

@testable import WamaduCore

@Suite struct CustomerColorTests {
    @Test func fixedOrderOfEightColors() {
        #expect(CustomerColor.allCases == [.blue, .purple, .orange, .teal, .pink, .green, .indigo, .brown])
    }

    @Test func firstCustomerGetsFirstColor() {
        #expect(CustomerColor.nextIndex(used: []) == 0)
    }

    @Test func lowestUnusedIndexWins() {
        #expect(CustomerColor.nextIndex(used: [0, 1, 3]) == 2)
        #expect(CustomerColor.nextIndex(used: [1, 2, 3, 4, 5, 6, 7]) == 0)
    }

    @Test func allUsedOnceStartsOverAtFirst() {
        #expect(CustomerColor.nextIndex(used: Array(0...7)) == 0)
    }

    @Test func allUsedPicksLeastUsedLowestOnTie() {
        #expect(CustomerColor.nextIndex(used: Array(0...7) + [0, 1, 2]) == 3)
        #expect(CustomerColor.nextIndex(used: Array(0...7) + Array(0...7) + [0, 1, 2, 3, 4, 6, 7]) == 5)
    }
}
