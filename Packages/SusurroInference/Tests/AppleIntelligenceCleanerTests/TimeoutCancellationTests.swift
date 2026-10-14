import CoreTestSupport
import Domain
import Pipeline
import Testing
import TextShaping

@testable import AppleIntelligenceCleaner

/// What the stage's limit does to a model call that has not answered by then: the call is cancelled where it runs, in
/// the engine, instead of being left to finish unseen, and the next call does not wait behind it.
@Suite("Apple Intelligence cleaner timeout", .timeLimit(.minutes(1)))
struct TimeoutCancellationTests {
    private func input(_ transcript: String = "hola equipo") -> CleanupInput {
        CleanupInput(
            transcript: transcript, style: StyleProfile(category: .email, tone: .formal, source: .default),
            vocabulary: [], cursor: nil)
    }

    private func stage(_ cleaner: AppleIntelligenceCleaner, clock: ManualClock) -> CleanupStage {
        CleanupStage(isEnabled: { true }, cleaner: { cleaner }, sleep: { try await clock.sleep(for: $0) })
    }

    @Test("a call that runs out of time sees its task cancelled in the engine, and the raw text is used")
    func engineSeesTheCancellation() async throws {
        let clock = ManualClock()
        let engine = FakeFoundationModelsEngine(gated: true)
        let stage = stage(AppleIntelligenceCleaner(engine: engine), clock: clock)
        let running = Task { try await stage.run(input()) }
        await engine.entered.wait()
        await clock.waitForSleeps(1)
        clock.advance(by: .seconds(6))

        let result = try await running.value
        #expect(result.fallbackReason == .timeout)
        #expect(result.finalText == "hola equipo")
        // Nobody released the engine: it left because its task was cancelled.
        await engine.returned.wait()
        #expect(engine.wasCancelledOnResume == true)
    }

    @Test("the call after one that timed out does not queue behind it")
    func nextCallIsNotBlocked() async throws {
        let clock = ManualClock()
        let engine = FakeFoundationModelsEngine(answer: "Hola, equipo.", gated: true)
        let cleaner = AppleIntelligenceCleaner(engine: engine)
        let stage = stage(cleaner, clock: clock)
        let first = Task { try await stage.run(input()) }
        await engine.entered.wait()
        await clock.waitForSleeps(1)
        clock.advance(by: .seconds(6))
        #expect(try await first.value.fallbackReason == .timeout)
        await engine.returned.wait()

        engine.release()
        let second = try await stage.run(input("adios equipo"))
        #expect(second.fallbackReason == nil)
        #expect(second.cleaned == "Hola, equipo.")
        #expect(await cleaner.queuedCalls == 0)
    }

    @Test("a call that is cancelled with the dictation sees the cancellation in the engine too")
    func dictationCancelReachesTheEngine() async throws {
        let clock = ManualClock()
        let engine = FakeFoundationModelsEngine(gated: true)
        let stage = stage(AppleIntelligenceCleaner(engine: engine), clock: clock)
        let running = Task { try await stage.run(input()) }
        await engine.entered.wait()
        running.cancel()

        await #expect(throws: CancellationError.self) { try await running.value }
        await engine.returned.wait()
        #expect(engine.wasCancelledOnResume == true)
    }
}
