import Domain
import TextShaping

/// Cleans a transcript with Apple's on-device language model, so nothing leaves the Mac. It takes local requests only.
///
/// The prompt is `PromptBuilder`'s, and the model samples greedily, so the same input gives the same text. Calls run one
/// at a time: an actor lets a second call start while the first awaits the model, so calls wait their turn in a queue of
/// their own.
public actor AppleIntelligenceCleaner: TranscriptCleaner {
    private struct Waiter {
        let id: Int
        let continuation: CheckedContinuation<Void, any Error>
    }

    public nonisolated let id = CleanerProviderID.appleIntelligence
    public nonisolated let locality = Locality.local
    public nonisolated let budget = ProviderBudget.foundationModels

    private let engine: any FoundationModelsEngine
    private var busy = false
    private var waiters: [Waiter] = []
    private var waiterCount = 0

    public init() {
        self.init(engine: LiveFoundationModelsEngine())
    }

    public init(engine: any FoundationModelsEngine) {
        self.engine = engine
    }

    /// The most tokens a reply may run to. Measured on this model, Spanish takes about 0.23 tokens a character and
    /// English about 0.21, and a cleaned text is about as long as the transcript, so half a token a character is more
    /// than twice what a faithful reply needs. A few tokens more cover a very short transcript.
    static func responseTokenLimit(forTranscriptCharacters count: Int) -> Int {
        count / 2 + 48
    }

    /// How many calls wait behind the one running.
    var queuedCalls: Int { waiters.count }

    public func availability() async -> CleanerAvailability {
        switch engine.availability() {
        case .available:
            .available
        case .unavailable(.deviceNotEligible):
            .unavailable("This Mac does not support Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            .unavailable("Apple Intelligence is turned off in System Settings.")
        case .unavailable(.modelNotReady):
            .unavailable("The Apple Intelligence model is not ready yet.")
        case .unavailable(.other):
            .unavailable("Apple Intelligence is not available.")
        }
    }

    public func clean(_ payload: CleanupPayload) async throws -> String {
        let request = try payload.requireLocal()
        let prompt = PromptBuilder.build(request)
        try await waitForTurn()
        defer { endTurn() }
        // A turn handed over at the moment of cancellation arrives as a normal wake-up.
        try Task.checkCancellation()
        do {
            return try await engine.generate(
                EngineRequest(
                    instructions: prompt.system, prompt: prompt.user, sampling: .greedy,
                    maximumResponseTokens: Self.responseTokenLimit(forTranscriptCharacters: request.transcript.count)))
        } catch let error as CancellationError {
            throw error
        } catch EngineError.guardrailViolation {
            throw CleanerError.guardrail
        } catch EngineError.contextWindowExceeded {
            throw CleanerError.contextWindowExceeded
        } catch EngineError.failed(let description) {
            throw CleanerError.failed(description)
        } catch {
            throw CleanerError.failed(String(describing: error))
        }
    }

    // MARK: Turns

    private func waitForTurn() async throws {
        guard busy else {
            busy = true
            return
        }
        waiterCount += 1
        let id = waiterCount
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                enqueue(continuation, id: id)
            }
        } onCancel: {
            Task { await self.abandonTurn(id) }
        }
    }

    private func enqueue(_ continuation: CheckedContinuation<Void, any Error>, id: Int) {
        // A cancellation that arrived before the handler was installed would never find this waiter.
        if Task.isCancelled {
            continuation.resume(throwing: CancellationError())
        } else {
            waiters.append(Waiter(id: id, continuation: continuation))
        }
    }

    private func abandonTurn(_ id: Int) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    /// Hands the turn to the next waiter, or frees it.
    private func endTurn() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }
}
