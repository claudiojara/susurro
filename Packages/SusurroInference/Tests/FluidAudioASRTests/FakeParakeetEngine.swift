import CoreTestSupport
import Synchronization

@testable import FluidAudioASR

/// A scripted engine. It never touches a model, the disk, or the network.
final class FakeParakeetEngine: ParakeetEngine {
    struct Transcription: Equatable, Sendable {
        let samples: [Float]
        let language: String?
    }

    /// What one call to `load` does: report these fractions, optionally wait for `releaseLoad()`, then finish or fail.
    struct LoadPlan: Sendable {
        var progress: [Double] = []
        var failure: (any Error)?
        var gated = false
    }

    private struct State {
        var plans: [LoadPlan]
        var loads = 0
        var transcriptions: [Transcription] = []
        var active = 0
        var peakActive = 0
    }

    /// What FluidAudio needs: 300 ms at 16 kHz.
    let minimumSampleCount = 4_800
    /// Opens once for every `transcribe` call that enters the engine.
    let entered = Gate()

    private let state: Mutex<State>
    private let loadGate = Gate()
    private let transcriptionGate = Gate()
    private let gatedTranscription: Bool
    private let respond: @Sendable ([Float]) throws -> String

    /// `loads` has one plan per call and the last one repeats. A `gatedTranscription` engine suspends in `transcribe`
    /// until `releaseTranscription()`, and honors cancellation while it waits. By default the text names the clip's
    /// length, so a result says which clip produced it.
    init(
        loads: [LoadPlan] = [LoadPlan()],
        gatedTranscription: Bool = false,
        respond: @escaping @Sendable ([Float]) throws -> String = { "samples:\($0.count)" }
    ) {
        state = Mutex(State(plans: loads))
        self.gatedTranscription = gatedTranscription
        self.respond = respond
    }

    var loadCount: Int { state.withLock { $0.loads } }
    var transcriptions: [Transcription] { state.withLock { $0.transcriptions } }
    /// The most transcriptions that were inside the engine at the same time.
    var peakActiveTranscriptions: Int { state.withLock { $0.peakActive } }

    func releaseLoad() { loadGate.open() }
    func releaseTranscription() { transcriptionGate.open() }

    func load(progress: @escaping @Sendable (Double) -> Void) async throws {
        let plan = state.withLock { state -> LoadPlan in
            state.loads += 1
            return state.plans.count > 1 ? state.plans.removeFirst() : state.plans[0]
        }
        for fraction in plan.progress { progress(fraction) }
        if plan.gated { await loadGate.wait() }
        if let failure = plan.failure { throw failure }
    }

    func transcribe(_ samples: [Float], language: String?) async throws -> String {
        state.withLock { state in
            state.transcriptions.append(Transcription(samples: samples, language: language))
            state.active += 1
            state.peakActive = max(state.peakActive, state.active)
        }
        defer { state.withLock { $0.active -= 1 } }
        entered.open()
        if gatedTranscription {
            await transcriptionGate.wait()
            try Task.checkCancellation()
        }
        return try respond(samples)
    }
}
