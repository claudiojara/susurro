import CoreTestSupport
import Domain
import Pipeline
import Synchronization
import Testing

@Suite("Recognition runner", .timeLimit(.minutes(1)))
struct RecognitionRunnerTests {
    private static let cloudID = ASRProviderID("cloud-fake")
    private static let appleID = ASRProviderID("apple-fake")
    private static let clip = AudioClip(samples: [Float](repeating: 0.1, count: AudioClip.sampleRate))

    private struct Failure: Error {}

    /// Collects the progress the runner reports.
    private final class Progress: Sendable {
        private let reported = Mutex<[Double?]>([])
        var values: [Double?] { reported.withLock { $0 } }
        func report(_ value: Double?) { reported.withLock { $0.append(value) } }
    }

    private struct Rig {
        let settings = InMemorySettingsStore()
        let diagnostics = RecordingDiagnostics()
        let sleeper: FakeSleeper
        let runner: RecognitionRunner

        init(
            _ providers: [FakeRecognizer],
            selected: ASRProviderID? = nil,
            languageProvider: ASRProviderID? = nil,
            guardian: LanguageGuard? = nil,
            sleeper: FakeSleeper = FakeSleeper(),
            sleep: (@Sendable (Duration) async throws -> Void)? = nil
        ) {
            self.sleeper = sleeper
            if let selected { settings.set(selected.rawValue, for: RecognitionSettings.provider) }
            let registry = RecognizerRegistry(
                providers: providers, languageProvider: languageProvider, settings: settings,
                credentials: AllKeys())
            // A settings store is a class, so the preference and the registry see the same values.
            runner = RecognitionRunner(
                registry: registry, language: SettingsLanguagePreference(settings: settings),
                languageGuard: guardian, diagnostics: diagnostics,
                sleep: sleep ?? { [sleeper] in try await sleeper.sleep($0) })
        }
    }

    private struct AllKeys: ProviderCredentials {
        func hasKey(for provider: ASRProviderID) -> Bool { true }
    }

    private static func parakeet(
        _ text: String = "hola", readiness: [RecognizerReadiness] = [.ready], failure: (any Error)? = nil,
        limit: Duration? = nil
    ) -> FakeRecognizer {
        FakeRecognizer(
            readiness: readiness, transcript: text, failure: failure, id: .parakeetV3, maxClipDuration: limit)
    }

    private static func run(
        _ rig: Rig, vocabulary: [String] = [], boostTerms: [String] = [], progress: Progress = Progress()
    ) async throws -> RecognitionOutcome {
        try await rig.runner.run(
            clip, vocabulary: vocabulary, boostTerms: boostTerms, progress: { progress.report($0) })
    }

    // MARK: Language and vocabulary

    @Test("the language is pinned to Spanish when the user wants it guaranteed, and left to the recognizer otherwise")
    func pinnedLanguage() async throws {
        let recognizer = Self.parakeet()
        let rig = Rig([recognizer])

        _ = try await Self.run(rig)
        rig.settings.set(SpeechLanguageMode.fast, for: RecognitionSettings.languageMode)
        _ = try await Self.run(rig)

        #expect(recognizer.receivedOptions.map(\.language) == ["es", nil])
    }

    @Test("vocabulary reaches the provider, and a provider without biasing succeeds when given 5 terms")
    func vocabulary() async throws {
        let recognizer = Self.parakeet("hecho")
        let terms = ["Susurro", "Parakeet", "FluidAudio", "Silero", "Tuminuta"]
        let outcome = try await Self.run(Rig([recognizer]), vocabulary: terms)

        #expect(outcome.text == "hecho")
        #expect(recognizer.receivedOptions.map(\.vocabulary) == [terms])
    }

    @Test("the terms to boost reach the provider apart from the vocabulary, and are none unless the caller names them")
    func boostTerms() async throws {
        let recognizer = Self.parakeet()
        let rig = Rig([recognizer])

        _ = try await Self.run(rig, vocabulary: ["Acme", "Kaelthorn"])
        _ = try await Self.run(rig, vocabulary: ["Acme", "Kaelthorn"], boostTerms: ["Kaelthorn"])

        #expect(recognizer.receivedOptions.map(\.boostTerms) == [[], ["Kaelthorn"]])
        #expect(recognizer.receivedOptions.map(\.vocabulary) == [["Acme", "Kaelthorn"], ["Acme", "Kaelthorn"]])
    }

    // MARK: Results

    @Test("the outcome names the provider and the text, with no fallback")
    func outcome() async throws {
        let outcome = try await Self.run(Rig([Self.parakeet("hola mundo")]))

        #expect(outcome == RecognitionOutcome(text: "hola mundo", provider: .parakeetV3))
    }

    @Test("a blank transcript is a blank outcome, for the pipeline to end as no speech", arguments: ["", "   ", "\n"])
    func blank(text: String) async throws {
        let outcome = try await Self.run(Rig([Self.parakeet(text)]))

        #expect(outcome.isBlank)
    }

    @Test("a clip longer than the recognizer takes is split, and the transcripts are joined")
    func longClip() async throws {
        let recognizer = Self.parakeet("hola", limit: .seconds(0.4))
        let outcome = try await Self.run(Rig([recognizer]))

        #expect(recognizer.transcribedClips.count == 3)
        #expect(outcome.text == "hola hola hola")
    }

    // MARK: Failure, timeout, and fallback

    @Test("a local failure is final, and says what failed")
    func localFailure() async {
        let rig = Rig([Self.parakeet(failure: Failure())])

        await #expect(throws: PipelineError.recognitionFailed(String(describing: Failure()))) {
            try await Self.run(rig)
        }
    }

    @Test("a call that takes longer than the limit fails the attempt with a timeout")
    func timeout() async throws {
        let clock = ManualClock()
        let recognizer = FakeRecognizer(gated: true, id: .parakeetV3)
        let rig = Rig([recognizer], sleep: { try await clock.sleep(for: $0) })
        let work = Task { try await Self.run(rig) }
        await recognizer.transcribeEntered.wait()
        await clock.waitForSleeps(1)

        clock.advance(by: DictationLimits.transcriptionTimeout)
        let result = await work.result

        if case .failure(let error) = result {
            #expect(error as? PipelineError == .timedOut(.transcription))
        } else {
            Issue.record("the attempt returned a text")
        }
    }

    @Test("a cloud failure is tried once more on this Mac, and the outcome names the provider that wrote the text")
    func cloudOutage() async throws {
        let transport = SpyNetworkTransport(failing: true)
        let cloud = FakeRecognizer(id: Self.cloudID, locality: .cloud, transport: transport)
        let local = Self.parakeet("hola desde casa")
        let rig = Rig([local, cloud], selected: Self.cloudID)
        rig.settings.set(true, for: RecognitionSettings.cloudEnabled(for: Self.cloudID))

        let outcome = try await Self.run(rig)

        #expect(
            outcome
                == RecognitionOutcome(text: "hola desde casa", provider: .parakeetV3, fallbackReason: "cloud-failure"))
        #expect(transport.sent.count == 1)
        #expect(local.transcribedClips == [Self.clip])
    }

    @Test("a local provider that fails does not fall back to itself")
    func noFallbackForLocal() async {
        let local = Self.parakeet(failure: Failure())
        let rig = Rig([local])

        await #expect(throws: PipelineError.self) { try await Self.run(rig) }
        #expect(local.transcribedClips.count == 1)
    }

    // MARK: Model readiness

    @Test("a dictation that ends while the model loads at 40% waits for readiness and publishes the progress")
    func waitsForReadiness() async throws {
        let recognizer = Self.parakeet("hola", readiness: [.loading(progress: 0.4)])
        let sleeper = FakeSleeper(blocksPauses: true)
        let rig = Rig([recognizer], sleeper: sleeper)
        let progress = Progress()
        let work = Task { try await Self.run(rig, progress: progress) }
        await sleeper.entered(DictationLimits.readinessPollInterval).wait()

        #expect(progress.values == [0.4])
        #expect(recognizer.transcribedClips.isEmpty)
        recognizer.setReadiness(.ready)
        sleeper.fire(DictationLimits.readinessPollInterval)
        let outcome = try await work.value

        #expect(outcome.text == "hola")
        #expect(progress.values == [0.4, nil])
        #expect(recognizer.transcribedClips == [Self.clip])
    }

    @Test("a model that is not installed fails with the error that sends the user to settings")
    func notInstalled() async {
        let recognizer = Self.parakeet(readiness: [.notInstalled])

        await #expect(throws: PipelineError.recognizerNotInstalled) { try await Self.run(Rig([recognizer])) }
        #expect(PipelineError.recognizerNotInstalled.remedy == .settings)
        #expect(recognizer.transcribedClips.isEmpty)
    }

    @Test("a model whose load failed fails with the reason and whether to try again")
    func unavailable() async {
        let recognizer = Self.parakeet(readiness: [.unavailable("no network", retryable: true)])

        await #expect(throws: PipelineError.recognizerUnavailable("no network", retryable: true)) {
            try await Self.run(Rig([recognizer]))
        }
    }

    @Test("progress that stops advancing ends in a timeout after the stall budget")
    func stalled() async {
        let stalled = Self.parakeet(readiness: [.loading(progress: 0.5)])
        let rig = Rig([stalled])

        await #expect(throws: PipelineError.timedOut(.readiness)) { try await Self.run(rig) }
        #expect(
            rig.sleeper.pauseCount == Int(DictationLimits.readinessStallTimeout / DictationLimits.readinessPollInterval)
        )
    }

    // MARK: Language guard

    private static let english = [
        "We big.": [LanguageGuess(code: "en", confidence: 0.9), LanguageGuess(code: "es", confidence: 0.02)],
        "muy bien": [LanguageGuess(code: "es", confidence: 0.9)],
    ]

    private static func guardRig(
        parakeet text: String = "We big.", alternative: FakeRecognizer? = nil,
        mode: SpeechLanguageMode = .guaranteedSpanish
    ) -> Rig {
        let apple = alternative ?? FakeRecognizer(transcript: "muy bien", id: appleID)
        let rig = Rig(
            [parakeet(text), apple], languageProvider: appleID,
            guardian: LanguageGuard(detector: FakeLanguageDetector(english)))
        rig.settings.set(mode, for: RecognitionSettings.languageMode)
        return rig
    }

    @Test("a transcript in the wrong language is transcribed again by the provider that honors the language")
    func languageDrift() async throws {
        let apple = FakeRecognizer(transcript: "muy bien", id: Self.appleID)
        let rig = Self.guardRig(alternative: apple)
        let outcome = try await Self.run(rig)

        #expect(
            outcome == RecognitionOutcome(text: "muy bien", provider: Self.appleID, fallbackReason: "language-drift"))
        #expect(apple.receivedOptions.map(\.language) == ["es"])
        #expect(rig.diagnostics.events == [.languageDriftDetected])
    }

    @Test("a Spanish transcript, or the fast mode, never asks the second provider")
    func noDrift() async throws {
        let apple = FakeRecognizer(transcript: "otra cosa", id: Self.appleID)
        let spanish = Self.guardRig(parakeet: "muy bien", alternative: apple)
        let fast = Self.guardRig(alternative: apple, mode: .fast)

        #expect(try await Self.run(spanish).text == "muy bien")
        #expect(try await Self.run(fast).text == "We big.")
        #expect(apple.transcribedClips.isEmpty)
    }

    @Test("when nothing can do better, the transcript is kept, with the reason, and the unknown tokens are removed")
    func driftUnresolved() async throws {
        let failing = FakeRecognizer(failure: Failure(), id: Self.appleID)
        let notReady = FakeRecognizer(readiness: [.notInstalled], id: Self.appleID)
        let stillWrong = FakeRecognizer(transcript: "We big.", id: Self.appleID)

        for alternative in [failing, notReady, stillWrong] {
            let outcome = try await Self.run(Self.guardRig(alternative: alternative))
            #expect(
                outcome
                    == RecognitionOutcome(
                        text: "We big.", provider: .parakeetV3, fallbackReason: "language-drift-unresolved"))
        }
        let cleaned = try await Self.run(Self.guardRig(parakeet: "<unk>Ghazda.<unk>"))
        #expect(cleaned.text == "muy bien")
        let noAlternative = Rig(
            [Self.parakeet("<unk>Ghazda.<unk>")], guardian: LanguageGuard(detector: FakeLanguageDetector()))
        let kept = try await Self.run(noAlternative)
        #expect(kept.text == "Ghazda.")
        #expect(kept.fallbackReason == "language-drift-unresolved")
    }
}
