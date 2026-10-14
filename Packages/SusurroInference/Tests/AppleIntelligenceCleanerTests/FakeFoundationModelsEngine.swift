import CoreTestSupport
import Synchronization

@testable import AppleIntelligenceCleaner

/// A model with scripted availability and a fixed answer. It records every request, and tells how many were running at
/// once. A `gated` engine suspends in `generate` until `release()`, after signalling `entered`.
final class FakeFoundationModelsEngine: FoundationModelsEngine {
    private struct State {
        var availability: EngineAvailability
        var requests: [EngineRequest] = []
        var active = 0
        var peakActive = 0
    }

    let entered = Gate()
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

    func release() { gate?.open() }

    func availability() -> EngineAvailability { state.withLock { $0.availability } }

    func generate(_ request: EngineRequest) async throws -> String {
        state.withLock { state in
            state.requests.append(request)
            state.active += 1
            state.peakActive = max(state.peakActive, state.active)
        }
        defer { state.withLock { $0.active -= 1 } }
        entered.open()
        await gate?.wait()
        try Task.checkCancellation()
        return try result.get()
    }
}
