import CoreTestSupport
import Testing

@testable import Presentation

@Suite("Level throttle")
struct LevelThrottleTests {
    private func throttle(on clock: ManualClock) -> LevelThrottle {
        let origin = clock.now
        return LevelThrottle(uptime: { origin.duration(to: clock.now) })
    }

    @Test("100 samples within 100 ms deliver at most 3, and the first is delivered at once")
    func burstOfLevels() {
        let clock = ManualClock()
        var sut = throttle(on: clock)
        var delivered: [Double] = []

        for index in 0..<100 {
            if let level = sut.accept(Double(index) / 100) { delivered.append(level) }
            clock.advance(by: .milliseconds(1))
        }

        #expect(delivered.count <= 3)
        #expect(delivered.first == 0)
        #expect(delivered.count >= 2)
    }

    @Test("a level that arrives after the interval is delivered")
    func afterTheInterval() {
        let clock = ManualClock()
        var sut = throttle(on: clock)

        #expect(sut.accept(0.1) == 0.1)
        clock.advance(by: .milliseconds(20))
        #expect(sut.accept(0.2) == nil)
        clock.advance(by: .milliseconds(20))
        #expect(sut.accept(0.3) == 0.3)
    }

    @Test("a steady stream of 100 levels a second is thinned to about 30")
    func steadyStream() {
        let clock = ManualClock()
        var sut = throttle(on: clock)
        var count = 0

        for _ in 0..<1_000 {  // ten seconds, one level every 10 ms
            if sut.accept(0.5) != nil { count += 1 }
            clock.advance(by: .milliseconds(10))
        }

        #expect(count <= 300)
        #expect(count >= 250)
    }

    @Test("after a reset the next level is delivered at once")
    func reset() {
        let clock = ManualClock()
        var sut = throttle(on: clock)
        _ = sut.accept(0.1)

        sut.reset()

        #expect(sut.accept(0.9) == 0.9)
    }
}
