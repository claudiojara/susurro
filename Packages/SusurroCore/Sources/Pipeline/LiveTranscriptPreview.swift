import Domain
import Synchronization

/// What the user is saying, as text, while the recording runs: the overlay style that shows it asks for it, and every
/// other style pays nothing. It is display only. The text that is pasted comes from the transcription of the finished
/// recording, which a partial never feeds and never queues ahead of.
///
/// A partial transcribes the newest `Policy.window` of audio on a background task of low priority. Partials never
/// overlap: the next one starts `Policy.interval` after the previous one ended, and only once enough new audio has
/// arrived. The end of the recording cancels the work: a partial that waits is dropped, and the text of one that is
/// already inside the engine is thrown away. ADR 0031 has the numbers behind the throttle.
public final class LiveTranscriptPreview: Sendable {
    public struct Policy: Sendable, Equatable {
        /// The time between the end of one partial and the start of the next.
        public var interval: Duration
        /// How much of the newest audio a partial transcribes. The model takes 15 s at most in one pass.
        public var window: Duration
        /// The least new audio since the last partial that makes another one worth running.
        public var minimumNewAudio: Duration

        public init(interval: Duration, window: Duration, minimumNewAudio: Duration) {
            self.interval = interval
            self.window = window
            self.minimumNewAudio = minimumNewAudio
        }

        public static let standard = Policy(
            interval: .seconds(1), window: .seconds(12), minimumNewAudio: .milliseconds(500))
    }

    private struct State {
        var generation = 0
        var isActive = false
        var worker: Task<Void, Never>?
        /// The newest audio, at most twice the window, so that trimming it is rare.
        var buffer: [Float] = []
        /// Whether audio older than the buffer was dropped, which cuts the first word of a partial in two.
        var trimmed = false
        var received = 0
        var transcribedUpTo = 0
    }

    /// The text of each partial, and an empty text when the recording ends. Only the newest value is kept for a slow
    /// reader. It has a single consumer.
    public nonisolated let partials: AsyncStream<String>

    private let continuation: AsyncStream<String>.Continuation
    private let policy: Policy
    private let clock: any Clock<Duration>
    private let isEnabled: @Sendable () -> Bool
    private let recognizer: @Sendable () -> (any PartialSpeechRecognizing)?
    private let language: @Sendable () -> String?
    private let state = Mutex(State())

    /// - Parameters:
    ///   - isEnabled: Whether the overlay in use shows partials. It is asked as each recording starts.
    ///   - recognizer: What transcribes the partials, or nil when the recognizer in use cannot give them.
    ///   - language: The pinned language of the dictation, or nil to detect it.
    public init(
        policy: Policy = .standard,
        clock: any Clock<Duration> = ContinuousClock(),
        isEnabled: @escaping @Sendable () -> Bool,
        recognizer: @escaping @Sendable () -> (any PartialSpeechRecognizing)?,
        language: @escaping @Sendable () -> String?
    ) {
        self.policy = policy
        self.clock = clock
        self.isEnabled = isEnabled
        self.recognizer = recognizer
        self.language = language
        (partials, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// A preview over the recognizer the registry selects, which gives partials only when it runs on this Mac and can.
    public convenience init(
        policy: Policy = .standard,
        clock: any Clock<Duration> = ContinuousClock(),
        isEnabled: @escaping @Sendable () -> Bool,
        recognizers: RecognizerRegistry,
        language: any LanguagePreference
    ) {
        self.init(
            policy: policy, clock: clock, isEnabled: isEnabled,
            recognizer: { recognizers.partialRecognizer() },
            language: { language.mode().pinnedLanguage })
    }

    /// Starts the preview of a recording, ending the one before it. It does nothing when the preview is off or the
    /// recognizer cannot give partials.
    public func begin() {
        end()
        guard isEnabled(), let recognizer = recognizer() else { return }
        let language = language()
        state.withLock { state in
            state.generation += 1
            state.isActive = true
            let generation = state.generation
            state.worker = Task(priority: .utility) { [self] in
                await run(generation, recognizer: recognizer, language: language)
            }
        }
    }

    /// Adds audio of the recording. It is dropped while no preview runs.
    public func append(_ samples: [Float]) {
        let window = AudioClip.sampleIndex(at: policy.window)
        state.withLock { state in
            guard state.isActive else { return }
            state.buffer += samples
            state.received += samples.count
            if state.buffer.count > 2 * window {
                state.buffer.removeFirst(state.buffer.count - window)
                state.trimmed = true
            }
        }
    }

    /// Ends the preview: the partial in flight is cancelled and its text dropped, the audio is let go, and the preview
    /// clears. It does nothing when no preview runs.
    public func end() {
        let (wasActive, worker) = state.withLock { state -> (Bool, Task<Void, Never>?) in
            guard state.isActive else { return (false, nil) }
            let worker = state.worker
            state = State(generation: state.generation)
            return (true, worker)
        }
        guard wasActive else { return }
        worker?.cancel()
        continuation.yield("")
    }

    // MARK: The throttle

    private func run(_ generation: Int, recognizer: any PartialSpeechRecognizing, language: String?) async {
        while !Task.isCancelled {
            do { try await clock.sleep(for: policy.interval) } catch { return }
            guard let (clip, received, trimmed) = window(of: generation) else { continue }
            let text: String?
            do {
                text = try await recognizer.transcribePartial(clip, language: language)
            } catch is CancellationError {
                return
            } catch {
                continue  // A failed partial shows nothing; the dictation reports its own failures.
            }
            guard let text else { continue }  // The engine was busy; the same audio is tried again.
            publish(trimmed ? Self.droppingFirstWord(text) : text, received: received, generation: generation)
        }
    }

    /// The newest window of audio, when enough of it is new.
    private func window(of generation: Int) -> (AudioClip, received: Int, trimmed: Bool)? {
        let window = AudioClip.sampleIndex(at: policy.window)
        let minimum = AudioClip.sampleIndex(at: policy.minimumNewAudio)
        return state.withLock { state in
            guard state.isActive, state.generation == generation,
                state.received - state.transcribedUpTo >= minimum
            else { return nil }
            let cut = state.buffer.count > window
            let samples = cut ? Array(state.buffer.suffix(window)) : state.buffer
            return (AudioClip(samples: samples), state.received, state.trimmed || cut)
        }
    }

    private func publish(_ text: String, received: Int, generation: Int) {
        let current = state.withLock { state in
            guard state.isActive, state.generation == generation, !Task.isCancelled else { return false }
            state.transcribedUpTo = received
            return true
        }
        if current { continuation.yield(text) }
    }

    /// The text without its first word, which began before the window did.
    static func droppingFirstWord(_ text: String) -> String {
        let words = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        return words.count > 1 ? String(words[1]) : ""
    }
}

extension RecognizerRegistry {
    /// The selected recognizer, when it runs on this Mac and can give partial transcripts. A cloud recognizer never
    /// does: a partial would send audio, and cost, a second time.
    public func partialRecognizer() -> (any PartialSpeechRecognizing)? {
        let recognizer = selected()
        guard recognizer.locality == .local else { return nil }
        return recognizer as? any PartialSpeechRecognizing
    }
}
