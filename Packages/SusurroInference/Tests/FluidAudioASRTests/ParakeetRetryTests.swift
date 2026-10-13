import Domain
import Foundation
import Synchronization
import Testing

@testable import FluidAudioASR

@Suite("Parakeet load failures and retries", .timeLimit(.minutes(1)))
struct ParakeetRetryTests {
    private struct Offline: LocalizedError {
        var errorDescription: String? { "The Internet connection appears to be offline." }
    }

    /// Time that only moves when a test says so.
    private final class FakeNow: Sendable {
        private let origin = ContinuousClock.now
        private let elapsed = Mutex(Duration.zero)

        func advance(by duration: Duration) { elapsed.withLock { $0 += duration } }

        var now: @Sendable () -> ContinuousClock.Instant {
            { [self] in origin + elapsed.withLock { $0 } }
        }
    }

    /// A recognizer whose engine fails every load with `failure`, after it has failed once.
    private static func failedRecognizer(
        _ failure: any Error,
        policy: LoadRetryPolicy = LoadRetryPolicy()
    ) async -> (ParakeetRecognizer, FakeParakeetEngine, FakeNow) {
        let engine = FakeParakeetEngine(loads: [.init(failure: failure)])
        let time = FakeNow()
        let recognizer = ParakeetRecognizer(engine: engine, retryPolicy: policy, now: time.now)
        await recognizer.prepare()
        await recognizer.waitUntilUnavailable()
        return (recognizer, engine, time)
    }

    @Test("a failed load is unavailable, with the reason the failure gives")
    func failedLoadIsUnavailable() async {
        let (recognizer, _, _) = await Self.failedRecognizer(Offline())

        #expect(await recognizer.readiness() == .unavailable("The Internet connection appears to be offline."))
    }

    @Test("a failure that is not localized still gives a reason")
    func failureWithoutDescription() async {
        struct Broken: Error {}
        let (recognizer, _, _) = await Self.failedRecognizer(Broken())

        guard case .unavailable(let reason) = await recognizer.readiness() else {
            Issue.record("the recognizer should be unavailable")
            return
        }
        #expect(!reason.isEmpty)
    }

    @Test("prepare tries again only once the wait after the failure has passed")
    func retryWaitsForTheBackoff() async {
        let policy = LoadRetryPolicy()
        let (recognizer, engine, time) = await Self.failedRecognizer(Offline(), policy: policy)
        let wait = policy.delay(afterFailures: 1)!

        await recognizer.prepare()
        time.advance(by: wait - .milliseconds(1))
        await recognizer.prepare()
        #expect(engine.loadCount == 1)
        #expect(await recognizer.readiness() == .unavailable("The Internet connection appears to be offline."))

        time.advance(by: .milliseconds(1))
        await recognizer.prepare()
        await recognizer.waitUntilUnavailable()
        #expect(engine.loadCount == 2)
    }

    @Test("every failure in a row waits longer than the one before")
    func backoffGrows() async {
        let policy = LoadRetryPolicy()
        let (recognizer, engine, time) = await Self.failedRecognizer(Offline(), policy: policy)

        time.advance(by: policy.delay(afterFailures: 1)!)
        await recognizer.prepare()
        await recognizer.waitUntilUnavailable()
        #expect(engine.loadCount == 2)

        time.advance(by: policy.delay(afterFailures: 1)!)
        await recognizer.prepare()
        #expect(engine.loadCount == 2)

        time.advance(by: policy.delay(afterFailures: 2)! - policy.delay(afterFailures: 1)!)
        await recognizer.prepare()
        await recognizer.waitUntilUnavailable()
        #expect(engine.loadCount == 3)
    }

    @Test("a failure that trying again cannot fix is never retried")
    func permanentFailure() async {
        let (recognizer, engine, time) = await Self.failedRecognizer(PermanentLoadFailure(reason: "model is damaged"))

        time.advance(by: .seconds(24 * 3_600))
        await recognizer.prepare()

        #expect(engine.loadCount == 1)
        #expect(await recognizer.readiness() == .unavailable("model is damaged"))
    }

    @Test("after the last attempt it stops, and says so")
    func attemptsRunOut() async {
        let policy = LoadRetryPolicy(firstDelay: .seconds(1), longestDelay: .seconds(1), maxAttempts: 3)
        let (recognizer, engine, time) = await Self.failedRecognizer(Offline(), policy: policy)
        for _ in 1..<3 {
            time.advance(by: .seconds(1))
            await recognizer.prepare()
            await recognizer.waitUntilUnavailable()
        }
        #expect(engine.loadCount == 3)

        time.advance(by: .seconds(24 * 3_600))
        await recognizer.prepare()

        #expect(engine.loadCount == 3)
        let expected =
            "The Internet connection appears to be offline. (Gave up after 3 attempts; restart the app to try again.)"
        #expect(await recognizer.readiness() == .unavailable(expected))
    }

    @Test(
        "the wait after a failure doubles up to a ceiling, and attempts run out at the limit",
        arguments: [
            (LoadRetryPolicy(), 1, Duration?.some(.seconds(10))),
            (LoadRetryPolicy(), 2, .seconds(20)),
            (LoadRetryPolicy(), 5, .seconds(160)),
            (LoadRetryPolicy(), 6, nil),
            (LoadRetryPolicy(firstDelay: .seconds(100), longestDelay: .seconds(300), maxAttempts: 9), 2, .seconds(200)),
            (LoadRetryPolicy(firstDelay: .seconds(100), longestDelay: .seconds(300), maxAttempts: 9), 3, .seconds(300)),
            (LoadRetryPolicy(firstDelay: .seconds(100), longestDelay: .seconds(300), maxAttempts: 9), 8, .seconds(300)),
            (LoadRetryPolicy(firstDelay: .seconds(100), longestDelay: .seconds(300), maxAttempts: 9), 9, nil),
        ]
    )
    func policyDelays(policy: LoadRetryPolicy, failures: Int, expected: Duration?) {
        #expect(policy.delay(afterFailures: failures) == expected)
    }
}
