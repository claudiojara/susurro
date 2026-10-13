import Domain
import OSLog

extension ASRProviderID {
    public static let parakeetV3 = ASRProviderID("parakeet-v3")
}

/// Transcribes with Parakeet v3, a multilingual model that runs on this Mac. Call `prepare()` at launch to download and
/// load the model; until `readiness()` is `.ready`, `transcribe` refuses.
///
/// The pipeline hands over the whole clip in one call and does no chunking or trimming of its own. FluidAudio does
/// split audio longer than about 15 s internally (windows of about 15 s with 2 s of overlap) and was measured on clips
/// up to 151 s, which is why `maxClipDuration` is nil.
///
/// Inference is serialized: an actor lets a second call start while the first awaits the engine, so calls wait their
/// turn in a queue of their own.
public actor ParakeetRecognizer: SpeechRecognizer {
    private struct Waiter {
        let id: Int
        let continuation: CheckedContinuation<Void, any Error>
    }

    // `id`, `locality`, and `maxClipDuration` are not requirements of `SpeechRecognizer` yet. `id` and `locality` join
    // the port in 4a.6 and `maxClipDuration` in 4b.7, and this recognizer already answers them.
    public nonisolated let id = ASRProviderID.parakeetV3
    public nonisolated let locality = Locality.local
    /// Nil: no limit is needed, because FluidAudio chunks long clips itself.
    public nonisolated let maxClipDuration: Duration? = nil

    private static let logger = Logger(subsystem: "dev.claudiojara.susurro", category: "parakeet")

    private let engine: any ParakeetEngine
    private let retryPolicy: LoadRetryPolicy
    private let now: @Sendable () -> ContinuousClock.Instant
    private var modelState = ModelState.notLoaded
    private var failedLoads = 0
    /// When a failed load may be tried again. Nil after a failure that no retry can fix, or after the last attempt.
    private var retryNotBefore: ContinuousClock.Instant?
    private var progress = LoadProgress()
    private var subscribers: [Int: AsyncStream<RecognizerReadiness>.Continuation] = [:]
    private var subscriberCount = 0
    private var inferenceBusy = false
    private var waiters: [Waiter] = []
    private var waiterCount = 0

    public init() {
        self.init(engine: LiveParakeetEngine())
    }

    init(
        engine: any ParakeetEngine,
        retryPolicy: LoadRetryPolicy = LoadRetryPolicy(),
        now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
    ) {
        self.engine = engine
        self.retryPolicy = retryPolicy
        self.now = now
    }

    /// How many transcriptions wait behind the one running.
    var queuedTranscriptions: Int { waiters.count }

    public func readiness() async -> RecognizerReadiness {
        modelState.readiness
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
        continuation.yield(modelState.readiness)
        return stream
    }

    /// Starts downloading and loading the model, and returns at once. It does nothing while a load runs or after one
    /// succeeded. After a failed load it starts a new one once the wait of `LoadRetryPolicy` has passed, and never after
    /// a failure that no retry can fix or after the last attempt.
    public func prepare() async {
        switch modelState {
        case .loading, .ready: return
        case .failed:
            guard let retryNotBefore, now() >= retryNotBefore else { return }
        case .notLoaded: break
        }
        progress = LoadProgress()
        transition(to: .loading(progress: 0))
        Task { await load() }
    }

    public func transcribe(_ clip: AudioClip, options: RecognitionOptions) async throws -> RawTranscript {
        guard modelState == .ready else { throw RecognitionError.notReady }
        // A clip below the engine's minimum (FluidAudio: 4,800 samples, 300 ms) is blank, not an error. The coordinator
        // discards holds shorter than 300 ms by key timestamps, but the first audio chunk arrives after the key goes
        // down, so a hold of 300 ms can hold fewer samples than that, and the engine would reject it.
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
            failedLoads = 0
            transition(to: .ready)
        } catch {
            sink.finish()
            await relay.value
            // Only the error's type is public; its description can name paths and hosts.
            let kind = String(reflecting: type(of: error))
            Self.logger.error("The speech model did not load: \(kind, privacy: .public): \(String(describing: error))")
            loadFailed(with: error)
        }
    }

    private func loadFailed(with error: any Error) {
        failedLoads += 1
        var reason = error.localizedDescription
        if let permanent = error as? PermanentLoadFailure {
            reason = permanent.reason
            retryNotBefore = nil
        } else if let wait = retryPolicy.delay(afterFailures: failedLoads) {
            retryNotBefore = now() + wait
        } else {
            retryNotBefore = nil
            reason += " (Gave up after \(failedLoads) attempts; restart the app to try again.)"
        }
        // A permanent failure and the last attempt both leave no retry to wait for.
        transition(to: .failed(reason, retryable: retryNotBefore != nil))
    }

    private func advance(to fraction: Double) {
        guard case .loading = modelState, let next = progress.observe(fraction) else { return }
        transition(to: .loading(progress: next))
    }

    private func transition(to next: ModelState) {
        let before = modelState.readiness
        modelState = next
        guard next.readiness != before else { return }
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
