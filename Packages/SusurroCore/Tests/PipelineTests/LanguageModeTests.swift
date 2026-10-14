import CoreTestSupport
import Domain
import Pipeline
import Synchronization
import Testing

/// The scenarios of the "Language mode" requirement of the speech recognition spec, from the setting to the history
/// record.
@Suite("Language mode", .timeLimit(.minutes(1)))
struct LanguageModeTests {
    private static let languageID = ASRProviderID("apple-fake")
    private static let clip = AudioClip(samples: [Float](repeating: 0.1, count: AudioClip.sampleRate))
    private static let wrongLanguage = "We big."
    private static let answers: [String: [LanguageGuess]] = [
        wrongLanguage: [LanguageGuess(code: "en", confidence: 0.9), LanguageGuess(code: "es", confidence: 0.02)],
        "Muy bien.": [LanguageGuess(code: "es", confidence: 0.9)],
        "Hice el pull request y el deploy quedó listo": [
            LanguageGuess(code: "es", confidence: 0.9), LanguageGuess(code: "en", confidence: 0.05),
        ],
    ]

    /// A detector that counts how often it is asked, to show that the guard did not run.
    private final class CountingDetector: LanguageDetecting {
        private let answers: FakeLanguageDetector
        private let asked = Mutex(0)

        init(_ answers: [String: [LanguageGuess]]) {
            self.answers = FakeLanguageDetector(answers)
        }

        var timesAsked: Int { asked.withLock { $0 } }

        func hypotheses(for text: String, maximum: Int) -> [LanguageGuess] {
            asked.withLock { $0 += 1 }
            return answers.hypotheses(for: text, maximum: maximum)
        }
    }

    private struct Rig {
        let settings = InMemorySettingsStore()
        let diagnostics = RecordingDiagnostics()
        let history = InMemoryHistoryRepository()
        let recordings = FakeRecordingStore()
        let inserter = FakeTextInserter()
        let detector: CountingDetector
        let pipeline: DictationPipeline
        let runner: RecognitionRunner

        init(
            provider: FakeRecognizer, languageRecognizer: FakeRecognizer? = nil,
            mode: SpeechLanguageMode = .guaranteedSpanish
        ) {
            settings.set(mode, for: RecognitionSettings.languageMode)
            detector = CountingDetector(LanguageModeTests.answers)
            let registry = RecognizerRegistry(
                providers: [provider] + (languageRecognizer.map { [$0] } ?? []), defaultProvider: provider.id,
                languageProvider: languageRecognizer?.id, settings: settings)
            let sleeper = FakeSleeper()
            let sleep: @Sendable (Duration) async throws -> Void = { try await sleeper.sleep($0) }
            runner = RecognitionRunner(
                registry: registry, language: SettingsLanguagePreference(settings: settings),
                languageGuard: LanguageGuard(detector: detector), diagnostics: diagnostics, sleep: sleep)
            pipeline = DictationPipeline(
                recordings: recordings, history: history, detector: FakeVoiceActivityDetector(), runner: runner,
                inserter: inserter, diagnostics: diagnostics, sleep: sleep)
        }

        func transcribe() async throws -> RecognitionOutcome {
            try await runner.run(LanguageModeTests.clip, progress: { _ in })
        }

        /// A whole dictation of the clip, and the record it leaves.
        func dictate() async throws -> DictationRecord {
            let recording = recordings.stored(LanguageModeTests.clip)
            let result = await pipeline.process(DictationJob(recording: recording)) { _ in }
            #expect(result == .finished(.inserted))
            return try #require(try await history.page(offset: 0, limit: 10).first)
        }
    }

    @Test("a fresh install has the guaranteed Spanish mode")
    func defaultMode() {
        #expect(InMemorySettingsStore().value(for: RecognitionSettings.languageMode) == .guaranteedSpanish)
    }

    @Test("the provider is given Spanish as a hint, and its transcript goes through the guard all the same")
    func hintPassedNotTrusted() async throws {
        // The fake ignores the language it is asked for, as Parakeet does.
        let provider = FakeRecognizer(transcript: Self.wrongLanguage, id: .parakeetV3)
        let rig = Rig(provider: provider)

        _ = try await rig.transcribe()

        #expect(provider.receivedOptions.map(\.language) == ["es"])
        #expect(rig.detector.timesAsked == 1)
        #expect(rig.diagnostics.events == [.languageDriftDetected])
    }

    @Test("a drift is resolved by the language recognizer, and the record names it and the reason")
    func driftResolved() async throws {
        let provider = FakeRecognizer(transcript: Self.wrongLanguage, id: .parakeetV3)
        let language = FakeRecognizer(transcript: "Muy bien.", id: Self.languageID)
        let rig = Rig(provider: provider, languageRecognizer: language)

        let record = try await rig.dictate()

        #expect(record.rawText == "Muy bien.")
        #expect(record.asrProvider == Self.languageID)
        #expect(record.fallbackReason == "language-drift")
        #expect(language.receivedOptions.map(\.language) == ["es"])
        #expect(rig.inserter.insertedTexts == ["Muy bien."])
    }

    @Test("a drift nothing can resolve keeps the transcript without the unknown tokens, and the attempt does not fail")
    func driftUnresolved() async throws {
        let provider = FakeRecognizer(transcript: "<unk>Ghazda.<unk>", id: .parakeetV3)
        let language = FakeRecognizer(readiness: [.notInstalled], id: Self.languageID)
        let rig = Rig(provider: provider, languageRecognizer: language)

        let record = try await rig.dictate()

        #expect(record.rawText == "Ghazda.")
        #expect(record.asrProvider == .parakeetV3)
        #expect(record.fallbackReason == "language-drift-unresolved")
        #expect(record.status == .succeeded)
        #expect(rig.inserter.insertedTexts == ["Ghazda."])
    }

    @Test("a Spanish transcript with a few English words is left as it is, and no second recognizer runs")
    func spanishWithEnglishWords() async throws {
        let text = "Hice el pull request y el deploy quedó listo"
        let language = FakeRecognizer(transcript: "otra cosa", id: Self.languageID)
        let rig = Rig(provider: FakeRecognizer(transcript: text, id: .parakeetV3), languageRecognizer: language)

        let outcome = try await rig.transcribe()

        #expect(outcome == RecognitionOutcome(text: text, provider: .parakeetV3))
        #expect(language.transcribedClips.isEmpty)
        #expect(rig.diagnostics.events.isEmpty)
    }

    @Test("in the fast mode no language is passed and the guard does not run, whatever comes back")
    func fastMode() async throws {
        let provider = FakeRecognizer(transcript: Self.wrongLanguage, id: .parakeetV3)
        let language = FakeRecognizer(transcript: "Muy bien.", id: Self.languageID)
        let rig = Rig(provider: provider, languageRecognizer: language, mode: .fast)

        let outcome = try await rig.transcribe()

        #expect(outcome == RecognitionOutcome(text: Self.wrongLanguage, provider: .parakeetV3))
        #expect(provider.receivedOptions.map(\.language) == [nil])
        #expect(rig.detector.timesAsked == 0)
        #expect(language.transcribedClips.isEmpty)
        #expect(rig.diagnostics.events.isEmpty)
    }
}
