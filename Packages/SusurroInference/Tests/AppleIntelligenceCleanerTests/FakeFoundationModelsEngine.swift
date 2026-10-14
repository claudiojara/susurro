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
        var prewarmed: [String] = []
        var usedWarmSession: [Bool] = []
    }

    let entered = Gate()
    private let state: Mutex<State>
    private let result: Result<String, any Error>
    private let gate: Gate?
    /// What a prewarm leaves for the next request, as the live engine does with a session.
    private let warm = WarmSlot<Int>()

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
    /// The instructions of each prewarm, in order.
    var prewarmed: [String] { state.withLock { $0.prewarmed } }
    /// For each request, in order, whether it used the session that a prewarm had left.
    var usedWarmSession: [Bool] { state.withLock { $0.usedWarmSession } }

    func release() { gate?.open() }

    func availability() -> EngineAvailability { state.withLock { $0.availability } }

    func prewarm(instructions: String) async {
        let number = state.withLock { state in
            state.prewarmed.append(instructions)
            return state.prewarmed.count
        }
        warm.store(number, instructions: instructions)
    }

    func generate(_ request: EngineRequest) async throws -> String {
        let usedWarm = warm.take(instructions: request.instructions) != nil
        state.withLock { state in
            state.usedWarmSession.append(usedWarm)
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
