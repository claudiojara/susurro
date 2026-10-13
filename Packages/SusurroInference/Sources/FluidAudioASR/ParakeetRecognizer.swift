import Domain
import OSLog

extension ASRProviderID {
    public static let parakeetV3 = ASRProviderID("parakeet-v3")
}

/// Transcribes with Parakeet v3, a multilingual model that runs on this Mac. The whole clip goes to the engine in one
/// call, with no chunking and no trimming. Call `prepare()` at launch to download and load the model; until
/// `readiness()` is `.ready`, `transcribe` refuses.
///
/// Inference is serialized: an actor lets a second call start while the first awaits the engine, so calls wait their
/// turn in a queue of their own.
public actor ParakeetRecognizer: SpeechRecognizer {
    private struct Waiter {
        let id: Int
        let continuation: CheckedContinuation<Void, any Error>
    }

    public nonisolated let id = ASRProviderID.parakeetV3
    public nonisolated let locality = Locality.local
    public nonisolated let maxClipDuration: Duration? = nil

    private static let logger = Logger(subsystem: "dev.claudiojara.susurro", category: "parakeet")

    private let engine: any ParakeetEngine
    private var model = ModelState.notLoaded
    private var progress = LoadProgress()
    private var subscribers: [Int: AsyncStream<RecognizerReadiness>.Continuation] = [:]
    private var subscriberCount = 0
    private var inferenceBusy = false
    private var waiters: [Waiter] = []
    private var waiterCount = 0

    public init() {
        self.init(engine: LiveParakeetEngine())
    }

    init(engine: any ParakeetEngine) {
        self.engine = engine
    }

    /// How many transcriptions wait behind the one running.
    var queuedTranscriptions: Int { waiters.count }

    public func readiness() async -> RecognizerReadiness {
        model.readiness
    }

    /// Readiness now, then every change after it. The stream never finishes by itself.
    public func readinessChanges() -> AsyncStream<RecognizerReadiness> {
        let (stream, continuation) = AsyncStream.makeStream(of: RecognizerReadiness.self, bufferingPolicy: .unbounded)
        subscriberCount += 1
        let id = subscriberCount
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribe(id) }
        }
        continuation.yield(model.readiness)
        return stream
    }

    /// Starts downloading and loading the model, and returns at once. It does nothing while a load runs or after one
    /// succeeded, and starts a new load after a failed one.
    public func prepare() {
        switch model {
        case .loading, .ready: return
        case .notLoaded, .failed: break
        }
        progress = LoadProgress()
        transition(to: .loading(progress: 0))
        Task { await load() }
    }

    public func transcribe(_ clip: AudioClip, options: RecognitionOptions) async throws -> RawTranscript {
        guard model == .ready else { throw RecognitionError.notReady }
        guard clip.samples.count >= engine.minimumSampleCount else { return RawTranscript(text: "") }
        try await waitForTurn()
        defer { endTurn() }
        // A turn handed over at the moment of cancellation arrives as a normal wake-up.
        try Task.checkCancellation()
        do {
            return RawTranscript(text: try await engine.transcribe(clip.samples, language: options.language))
        } catch let error as CancellationError {
            throw error
        } catch let error as RecognitionError {
            throw error
        } catch {
            throw RecognitionError.engineFailed(String(describing: error))
        }
    }

    // MARK: Loading

    private func load() async {
        // The engine reports from any thread. A stream keeps the fractions in the order they were reported.
        let (fractions, sink) = AsyncStream.makeStream(of: Double.self)
        let relay = Task {
            for await fraction in fractions { advance(to: fraction) }
        }
        do {
            try await engine.load { sink.yield($0) }
            sink.finish()
            await relay.value
            transition(to: .ready)
        } catch {
            sink.finish()
            await relay.value
            Self.logger.error("The speech model did not load: \(String(describing: error), privacy: .public)")
            transition(to: .failed)
        }
    }

    private func advance(to fraction: Double) {
        guard case .loading = model, let next = progress.observe(fraction) else { return }
        transition(to: .loading(progress: next))
    }

    private func transition(to next: ModelState) {
        model = next
        for continuation in subscribers.values { continuation.yield(next.readiness) }
    }

    private func unsubscribe(_ id: Int) {
        subscribers[id] = nil
    }

    // MARK: Turns

    private func waitForTurn() async throws {
        guard inferenceBusy else {
            inferenceBusy = true
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
            inferenceBusy = false
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }
}
