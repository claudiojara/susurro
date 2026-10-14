import Testing

@testable import CoreTestSupport

@Suite("Test instant", .timeLimit(.minutes(1)))
struct TestInstantTests {
    @Test("an instant is a time since the clock began, which moves forward and measures the way to another")
    func arithmetic() {
        let start = TestInstant(offset: .seconds(2))
        let later = start.advanced(by: .milliseconds(500))

        #expect(later == TestInstant(offset: .milliseconds(2_500)))
        #expect(start.duration(to: later) == .milliseconds(500))
        #expect(later.duration(to: start) == .milliseconds(-500))
        #expect(start < later)
        #expect(!(later < start))
    }

    @Test("the manual clock begins at the zero instant, and its instants are the shared kind")
    func manualClockUsesIt() {
        let clock = ManualClock()
        let begin: TestInstant = clock.now

        clock.advance(by: .seconds(3))

        #expect(begin == TestInstant(offset: .zero))
        #expect(begin.duration(to: clock.now) == .seconds(3))
    }
}
