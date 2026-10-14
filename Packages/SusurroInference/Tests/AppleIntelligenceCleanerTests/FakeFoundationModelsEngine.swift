import CoreTestSupport
import Synchronization

@testable import AppleIntelligenceCleaner

/// A model with scripted availability and a fixed answer. It records every request, and tells how many were running at
/// once. A `gated` engine suspends in `generate` until `release()` or until its task is cancelled, after signalling
/// `entered`. When a call resumes it records whether its task was cancelled and signals `returned`.
final class FakeFoundationModelsEngine: FoundationModelsEngine {
    private struct State {
        var availability: EngineAvailability
        var requests: [EngineRequest] = []
        var active = 0
        var peakActive = 0
        var cancelledOnResume: Bool?
    }

    let entered = Gate()
    /// Opened when `generate` leaves, whichever way.
    let returned = Gate()
    private let state: Mutex<State>
    private let result: Result<String, any Error>
    private let gate: Gate?

    init(
        availability: EngineAvailability = .available, answer: String = "Hola, equipo.",
        failure: (any Error)? = nil, gated: Bool = false
    ) {
        state = Mutex(State(availability: availability))
        result = failure.map { .failure($0) } ?? .success(answer)
        gate = gated ? Gate() : nil
    }

    var requests: [EngineRequest] { state.withLock { $0.requests } }
    var peakActive: Int { state.withLock { $0.peakActive } }
    /// Whether the task of the last call that resumed was cancelled by then, or nil while none has resumed.
    var wasCancelledOnResume: Bool? { state.withLock { $0.cancelledOnResume } }

    func release() { gate?.open() }

    func availability() -> EngineAvailability { state.withLock { $0.availability } }

    func generate(_ request: EngineRequest) async throws -> String {
        state.withLock { state in
            state.requests.append(request)
            state.active += 1
            state.peakActive = max(state.peakActive, state.active)
        }
        defer {
            state.withLock { $0.active -= 1 }
            returned.open()
        }
        entered.open()
        await gate?.wait()
        state.withLock { $0.cancelledOnResume = Task.isCancelled }
        try Task.checkCancellation()
        return try result.get()
    }
}
