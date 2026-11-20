import Testing

@testable import Accounts

struct ConnMotionTests {
    @Test func reduceMotionRestsStill() {
        for t in stride(from: 0.0, to: 12.0, by: 0.7) { #expect(ConnMotion.floatOffset(at: t, reduce: true) == 0) }
    }

    @Test func floatLiftsAtMostFourAndNeverDips() {
        for t in stride(from: 0.0, to: 12.0, by: 0.1) {
            let y = ConnMotion.floatOffset(at: t, reduce: false)
            #expect(y <= 0 && y >= -ConnMotion.floatLift - 0.0001)
        }
        #expect(
            abs(ConnMotion.floatOffset(at: ConnMotion.floatPeriod / 2, reduce: false) + ConnMotion.floatLift) < 0.0001)
    }
}
