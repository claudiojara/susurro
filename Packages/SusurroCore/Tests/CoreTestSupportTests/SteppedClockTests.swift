import CoreTestSupport
import Testing

@Suite("Stepped clock", .timeLimit(.minutes(1)))
struct SteppedClockTests {
    @Test("a sleep returns at once and moves the clock by the time it slept, on the instants the manual clock uses")
    func sleepMovesTheClock() async throws {
        let clock = SteppedClock()
        let begin: TestInstant = clock.now

        try await clock.sleep(for: .seconds(4))

        #expect(begin == TestInstant(offset: .zero))
        #expect(begin.duration(to: clock.now) == .seconds(4))
        #expect(clock.sleeps == [.seconds(4)])
    }
}
