import Domain

extension ASRProviderID {
    /// The recognizer of the system's on-device speech framework.
    public static let appleSpeech = ASRProviderID("apple-speech")
}

/// Transcribes with the speech framework of macOS, on this Mac. Unlike Parakeet, which detects the language itself, it is
/// given the language and transcribes in it, so the pipeline asks it to transcribe again a clip that Parakeet answered in
/// the wrong language. It is slower to load and less exact on technical words, which is why it is the second choice.
///
/// Call `prepare()` at launch to install the assets of the language; until `readiness()` is `.ready`, `transcribe`
/// refuses. The language it prepares is `preparedLanguage`.
public actor AppleSpeechRecognizer: SpeechRecognizer {
    private enum State: Equatable {
        case notPrepared
        case installing(Double)
        case ready
        case failed(String, retryable: Bool)
    }

    public nonisolated let id = ASRProviderID.appleSpeech
    public nonisolated let locality = Locality.local
    public nonisolated let maxClipDuration: Duration? = nil

    /// The language `prepare()` installs: the one the user dictates in.
    public nonisolated let preparedLanguage: String

    private let engine: any AppleSpeechEngine
    private var state = State.notPrepared

    public init(preparedLanguage: String = "es") {
        self.init(engine: LiveAppleSpeechEngine(), preparedLanguage: preparedLanguage)
    }

    init(engine: any AppleSpeechEngine, preparedLanguage: String = "es") {
        self.engine = engine
        self.preparedLanguage = preparedLanguage
    }

    public func readiness() async -> RecognizerReadiness {
        switch state {
        case .notPrepared: .loading(progress: 0)
        case .installing(let progress): .loading(progress: progress)
        case .ready: .ready
        case .failed(let reason, let retryable): .unavailable(reason, retryable: retryable)
        }
    }

    /// Starts installing the language, and returns at once. It does nothing while an install runs or once the language
    /// is ready, and it tries again after a failure that another try may fix.
    public func prepare() async {
        switch state {
        case .installing, .ready: return
        case .failed(_, let retryable) where !retryable: return
        case .failed, .notPrepared: break
        }
        state = .installing(0)
        Task { await install() }
    }

    public func transcribe(_ clip: AudioClip, options: RecognitionOptions) async throws -> RawTranscript {
        guard state == .ready else { throw RecognitionError.notReady }
        let language = options.language ?? preparedLanguage
        do {
            return RawTranscript(text: try await engine.transcribe(clip.samples, language: language))
        } catch let error as CancellationError {
            throw error
        } catch let error as RecognitionError {
            throw error
        } catch {
            throw RecognitionError.engineFailed(String(describing: error))
        }
    }

    private func install() async {
        guard await engine.isSupported(language: preparedLanguage) else {
            state = .failed("This Mac cannot transcribe \(preparedLanguage) on the device.", retryable: false)
            return
        }
        // The engine reports from any thread. A stream keeps the fractions in the order they were reported.
        let (fractions, sink) = AsyncStream.makeStream(of: Double.self)
        let relay = Task {
            for await fraction in fractions { advance(to: fraction) }
        }
        do {
            try await engine.install(language: preparedLanguage) { sink.yield($0) }
            sink.finish()
            await relay.value
            state = .ready
        } catch {
            sink.finish()
            await relay.value
            state = .failed("The speech assets could not be installed.", retryable: true)
        }
    }

    private func advance(to fraction: Double) {
        guard case .installing(let current) = state else { return }
        state = .installing(max(current, min(max(fraction, 0), 0.99)))
    }
}
