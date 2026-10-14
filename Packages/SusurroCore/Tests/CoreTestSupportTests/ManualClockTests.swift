import Testing

@testable import CoreTestSupport

@Suite("Manual clock", .timeLimit(.minutes(1)))
struct ManualClockTests {
    /// Starts a sleep in its own task and returns once the clock holds it, so a later `advance` cannot miss it.
    private static func startSleep(
        on clock: ManualClock,
        for duration: Duration,
        suspendedBefore: Int
    ) async -> Task<Void, any Error> {
        let sleeper = Task { try await clock.sleep(for: duration) }
        await clock.waitForSleeps(suspendedBefore + 1)
        return sleeper
    }

    @Test("a sleep stays suspended until the clock reaches its deadline, to the nanosecond")
    func suspendsUntilTheDeadline() async throws {
        let clock = ManualClock()
        let sleeper = await Self.startSleep(on: clock, for: .seconds(5), suspendedBefore: 0)

        clock.advance(by: .seconds(5) - .nanoseconds(1))
        let pendingJustBefore = clock.pendingSleeps
        clock.advance(by: .nanoseconds(1))
        try await sleeper.value

        #expect(pendingJustBefore == 1)
        #expect(clock.pendingSleeps == 0)
    }

    @Test("a sleep is woken by its own deadline, not held back by an earlier one that is still waiting")
    func laterRegistrationWithEarlierDeadlineWakesFirst() async throws {
        let clock = ManualClock()
        let long = await Self.startSleep(on: clock, for: .seconds(3), suspendedBefore: 0)
        let short = await Self.startSleep(on: clock, for: .seconds(1), suspendedBefore: 1)

        clock.advance(by: .seconds(1))
        try await short.value

        #expect(clock.pendingSleeps == 1)
        #expect(clock.wakeOrder == [1])
        clock.advance(by: .seconds(2))
        try await long.value
        #expect(clock.wakeOrder == [1, 0])
    }

    @Test("one advance past several deadlines wakes the sleeps in deadline order, equal deadlines in call order")
    func wakesInDeadlineOrder() async throws {
        let clock = ManualClock()
        var sleepers: [Task<Void, any Error>] = []
        for (index, seconds) in [3, 1, 2, 1].enumerated() {
            sleepers.append(await Self.startSleep(on: clock, for: .seconds(seconds), suspendedBefore: index))
        }

        clock.advance(by: .seconds(10))
        for sleeper in sleepers { try await sleeper.value }

        #expect(clock.wakeOrder == [1, 3, 2, 0])
    }

    @Test("a sleep whose deadline has passed or is now returns without an advance", arguments: [-3, 0])
    func noTimeLeft(seconds: Int) async throws {
        let clock = ManualClock()

        try await clock.sleep(for: .seconds(seconds))

        #expect(clock.pendingSleeps == 0)
        #expect(clock.wakeOrder.isEmpty)
    }

    @Test("a sleep until an instant the clock has already passed returns at once")
    func deadlineAlreadyPassed() async throws {
        let clock = ManualClock()
        let start = clock.now
        clock.advance(by: .seconds(2))

        try await clock.sleep(until: start, tolerance: nil)

        #expect(clock.pendingSleeps == 0)
    }

    @Test("cancelling a sleep throws CancellationError and removes it from the clock")
    func cancellationThrows() async {
        let clock = ManualClock()
        let sleeper = await Self.startSleep(on: clock, for: .seconds(5), suspendedBefore: 0)

        sleeper.cancel()
        let result = await sleeper.result

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(clock.pendingSleeps == 0)
    }

    @Test("a cancelled sleep is not woken again, and the sleeps beside it are not affected")
    func cancelledSleepStaysCancelled() async throws {
        let clock = ManualClock()
        let cancelled = await Self.startSleep(on: clock, for: .seconds(2), suspendedBefore: 0)
        let other = await Self.startSleep(on: clock, for: .seconds(4), suspendedBefore: 1)

        cancelled.cancel()
        _ = await cancelled.result
        clock.advance(by: .seconds(3))

        #expect(clock.pendingSleeps == 1)
        #expect(clock.wakeOrder.isEmpty)
        clock.advance(by: .seconds(1))
        try await other.value
        #expect(clock.wakeOrder == [1])
    }

    @Test("a task cancelled before it sleeps throws without ever being suspended")
    func cancelledBeforeSleeping() async {
        let clock = ManualClock()
        let neverOpened = Gate()
        let sleeper = Task {
            await neverOpened.wait()  // returns when the task is cancelled
            try await clock.sleep(for: .seconds(5))
        }

        sleeper.cancel()
        let result = await sleeper.result

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(clock.pendingSleeps == 0)
        #expect(clock.suspendedSleeps == 0)
    }

    @Test("now only moves forward: an advance adds its duration, zero changes nothing, a negative one is ignored")
    func nowIsMonotonic() {
        let clock = ManualClock()
        let start = clock.now

        clock.advance(by: .seconds(2))
        clock.advance(by: .seconds(3))
        let afterTwoAdvances = start.duration(to: clock.now)
        clock.advance(by: .zero)
        clock.advance(by: .seconds(-4))

        #expect(afterTwoAdvances == .seconds(5))
        #expect(start.duration(to: clock.now) == .seconds(5))
        #expect(clock.now > start)
    }

    @Test("waiting for sleeps that already happened returns at once, and a later one waits for the sleep to start")
    func waitForSleeps() async throws {
        let clock = ManualClock()
        let first = Task { try await clock.sleep(for: .seconds(1)) }
        await clock.waitForSleeps(1)
        clock.advance(by: .seconds(1))
        try await first.value

        await clock.waitForSleeps(1)  // the first sleep is over, but it did happen
        let second = Task { try await clock.sleep(for: .seconds(1)) }
        await clock.waitForSleeps(2)

        #expect(clock.pendingSleeps == 1)
        clock.advance(by: .seconds(1))
        try await second.value
    }
}
