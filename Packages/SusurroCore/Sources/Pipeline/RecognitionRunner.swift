import Domain

/// What the recognition of a clip produced.
public struct RecognitionOutcome: Sendable, Equatable {
    /// The raw transcript, whole clip, in order. Blank when the recognizer heard no speech.
    public let text: String
    /// The recognizer that wrote it, which is not the selected one when a fallback ran.
    public let provider: ASRProviderID
    /// Why the first choice was left for another, when it was: "cloud-failure", "language-drift", or
    /// "language-drift-unresolved" (the transcript is in the wrong language and nothing could do better).
    public let fallbackReason: String?

    public init(text: String, provider: ASRProviderID, fallbackReason: String? = nil) {
        self.text = text
        self.provider = provider
        self.fallbackReason = fallbackReason
    }

    public var isBlank: Bool { text.allSatisfy(\.isWhitespace) }
}

/// Turns a clip into a raw transcript with the recognizer the registry selects.
///
/// - It waits for a model that is still loading, reporting its progress.
/// - It passes the pinned language (or none, for automatic detection), the vocabulary, and the dictionary terms to boost.
/// - It splits a clip that is longer than the recognizer takes, and bounds each call with a timeout.
/// - When a cloud recognizer fails, it tries the default local one once and says which one wrote the text.
/// - When the user wants the language guaranteed and the transcript comes back in another one, it transcribes the clip
///   again with a recognizer that honors the language, if the app has one.
public struct RecognitionRunner: Sendable {
    private let registry: RecognizerRegistry
    private let language: any LanguagePreference
    private let languageGuard: LanguageGuard?
    private let diagnostics: any DiagnosticsLog
    private let sleep: @Sendable (Duration) async throws -> Void

    /// - Parameters:
    ///   - languageGuard: What notices a transcript in the wrong language. Nil for no guard.
    ///   - sleep: Paces the readiness polls and times out the calls. Tests pass a fake.
    public init(
        registry: RecognizerRegistry,
        language: any LanguagePreference,
        languageGuard: LanguageGuard? = nil,
        diagnostics: any DiagnosticsLog = NoDiagnostics(),
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.registry = registry
        self.language = language
        self.languageGuard = languageGuard
        self.diagnostics = diagnostics
        self.sleep = sleep
    }

    /// - Parameters:
    ///   - vocabulary: Every term worth favoring: the dictionary and the names found around the cursor and on screen.
    ///   - boostTerms: The dictionary alone, for a recognizer that rescores its transcript against known terms.
    ///   - progress: Told the progress of the model's load while the clip waits for it, and nil when it is ready.
    public func run(
        _ clip: AudioClip,
        vocabulary: [String] = [],
        boostTerms: [String] = [],
        progress: @escaping @Sendable (Double?) async -> Void
    ) async throws -> RecognitionOutcome {
        let waiter = ReadinessWaiter(sleep: sleep)
        let selected = registry.selected()
        try await waiter.wait(for: selected, report: progress)

        let mode = language.mode()
        let options = RecognitionOptions(language: mode.pinnedLanguage, vocabulary: vocabulary, boostTerms: boostTerms)
        var used = selected
        var reason: String?
        var text: String
        do {
            text = try await transcribe(clip, with: selected, options: options)
        } catch {
            // A cloud failure is given a second chance on this Mac. Anything else, and a failure of that, is final.
            guard !Task.isCancelled, selected.locality == .cloud, let fallback = registry.fallback(from: selected)
            else { throw error }
            try await waiter.wait(for: fallback, report: progress)
            text = try await transcribe(clip, with: fallback, options: options)
            used = fallback
            reason = "cloud-failure"
        }

        if mode == .guaranteedSpanish, let languageGuard, languageGuard.hasDrifted(text) {
            diagnostics.record(.languageDriftDetected)
            if let retried = await retryHonoringLanguage(clip, options: options, after: used, guard: languageGuard) {
                return RecognitionOutcome(
                    text: retried.text, provider: retried.provider, fallbackReason: "language-drift")
            }
            reason = "language-drift-unresolved"
        }
        return RecognitionOutcome(
            text: LanguageGuard.removingUnknownTokens(from: text), provider: used.id, fallbackReason: reason)
    }

    /// Transcribes the clip again with the recognizer that honors the language. Nil when there is none, when it is not
    /// ready, when it fails, or when its answer is blank or in the wrong language too.
    private func retryHonoringLanguage(
        _ clip: AudioClip, options: RecognitionOptions, after used: any SpeechRecognizer,
        guard languageGuard: LanguageGuard
    ) async -> (text: String, provider: ASRProviderID)? {
        guard let alternative = registry.languageFallback(), alternative.id != used.id,
            await alternative.readiness() == .ready,
            let text = try? await transcribe(clip, with: alternative, options: options),
            !text.allSatisfy(\.isWhitespace), !languageGuard.hasDrifted(text)
        else { return nil }
        return (text, alternative.id)
    }

    /// One recognizer over the whole clip, a piece at a time when the recognizer takes only so much, each call bounded.
    private func transcribe(
        _ clip: AudioClip, with recognizer: any SpeechRecognizer, options: RecognitionOptions
    ) async throws -> String {
        let sleep = sleep
        do {
            return try await ChunkedTranscriber(limit: recognizer.maxClipDuration).transcribe(clip) { piece in
                try await withDeadline(
                    DictationLimits.transcriptionTimeout(forClip: piece.duration), stage: .transcription, sleep: sleep
                ) {
                    try await recognizer.transcribe(piece, options: options)
                }
            }.text
        } catch let error as PipelineError {
            throw error
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw PipelineError.recognitionFailed(String(describing: error))
        }
    }
}
