import Domain
import Synchronization

/// A cleaner with scripted availability and a fixed answer. It records every payload it is given. A `gated` cleaner
/// suspends in `clean` until `releaseCleaning()` or until it is cancelled, after signalling `entered`.
public final class FakeCleaner: TranscriptCleaner {
    public enum Answer: Sendable {
        case text(String)
        case failure(CleanerError)
        /// The answer is computed from the payload, for tests that echo it.
        case compute(@Sendable (CleanupPayload) -> String)
    }

    /// Opened when `clean` is entered.
    public let entered = Gate()
    public let id: CleanerProviderID
    public let locality: Locality
    public let budget: ProviderBudget
    private struct State {
        var availability: CleanerAvailability
        var answer: Answer
        var payloads: [CleanupPayload] = []
        var availabilityChecks = 0
    }
    private let state: Mutex<State>
    private let gate: Gate?

    public init(
        id: CleanerProviderID = .appleIntelligence,
        locality: Locality = .local,
        budget: ProviderBudget? = nil,
        availability: CleanerAvailability = .available,
        answer: Answer = .text("cleaned"),
        gated: Bool = false
    ) {
        self.id = id
        self.locality = locality
        self.budget = budget ?? (locality == .local ? .foundationModels : .cloud)
        state = Mutex(State(availability: availability, answer: answer))
        gate = gated ? Gate() : nil
    }

    /// The payloads `clean` received, in order.
    public var payloads: [CleanupPayload] { state.withLock { $0.payloads } }
    public var callCount: Int { payloads.count }
    public var availabilityChecks: Int { state.withLock { $0.availabilityChecks } }

    public func setAvailability(_ availability: CleanerAvailability) {
        state.withLock { $0.availability = availability }
    }

    public func setAnswer(_ answer: Answer) {
        state.withLock { $0.answer = answer }
    }

    public func releaseCleaning() { gate?.open() }

    public func availability() async -> CleanerAvailability {
        state.withLock { state in
            state.availabilityChecks += 1
            return state.availability
        }
    }

    public func clean(_ payload: CleanupPayload) async throws -> String {
        state.withLock { $0.payloads.append(payload) }
        entered.open()
        await gate?.wait()
        try Task.checkCancellation()
        let answer = state.withLock { $0.answer }
        switch answer {
        case .text(let text): return text
        case .failure(let error): throw error
        case .compute(let transform): return transform(payload)
        }
    }
}
