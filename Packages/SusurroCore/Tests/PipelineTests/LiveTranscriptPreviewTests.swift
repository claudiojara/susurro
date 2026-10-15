import CoreTestSupport
import Domain
import Testing

@testable import Pipeline

/// The partial transcripts of a recording are throttled and cancelled on a clock the test drives, so each test says
/// exactly when a partial may run and shows what it does not do.
@Suite("Live transcript preview", .timeLimit(.minutes(1)))
struct LiveTranscriptPreviewTests {
    private static let policy = LiveTranscriptPreview.Policy(
        interval: .seconds(1), window: .seconds(2), minimumNewAudio: .milliseconds(500))

    private struct Harness {
        let clock = ManualClock()
        let recognizer: FakePartialRecognizer
        let preview: LiveTranscriptPreview
        var partials: AsyncStream<String>.Iterator

        init(
            recognizer: FakePartialRecognizer = FakePartialRecognizer(), enabled: Bool = true,
            canTranscribe: Bool = true, language: String? = "es"
        ) {
            self.recognizer = recognizer
            preview = LiveTranscriptPreview(
                policy: LiveTranscriptPreviewTests.policy, clock: clock, isEnabled: { enabled },
                recognizer: { [recognizer] in canTranscribe ? recognizer : nil }, language: { language })
            partials = preview.partials.makeAsyncIterator()
        }

        /// Lets the throttle's next sleep end: waits until it is suspended, then moves the clock past it.
        func tick(_ sleeps: Int) async {
            await clock.waitForSleeps(sleeps)
            clock.advance(by: .seconds(1))
        }

        mutating func next() async -> String? { await partials.next() }
    }

    private static func audio(seconds: Double, value: Float = 0.1) -> [Float] {
        [Float](repeating: value, count: Int(seconds * Double(AudioClip.sampleRate)))
    }

    @Test("nothing is transcribed before the interval, and the audio so far is once it has passed")
    func firstPartialAfterTheInterval() async {
        var harness = Harness()
        harness.preview.begin()
        harness.preview.append(Self.audio(seconds: 1))

        await harness.clock.waitForSleeps(1)
        #expect(harness.recognizer.calls.isEmpty)
        harness.clock.advance(by: .seconds(1))

        #expect(await harness.next() == "hello")
        #expect(harness.recognizer.calls == [.init(clip: AudioClip(samples: Self.audio(seconds: 1)), language: "es")])
    }

    @Test("the next partial waits for the interval after the previous one ended, so two never overlap")
    func partialsDoNotOverlap() async {
        let recognizer = FakePartialRecognizer(answers: ["one", "two"], gated: true)
        var harness = Harness(recognizer: recognizer)
        harness.preview.begin()
        harness.preview.append(Self.audio(seconds: 1))
        await harness.tick(1)
        await recognizer.entered.wait()

        // While the first runs, time passes and audio arrives, and no second one starts or sleeps.
        harness.preview.append(Self.audio(seconds: 1))
        harness.clock.advance(by: .seconds(5))
        #expect(harness.clock.suspendedSleeps == 1)
        #expect(recognizer.calls.count == 1)

        recognizer.release()
        #expect(await harness.next() == "one")
        await harness.tick(2)
        await recognizer.entered.wait()
        recognizer.release()
        #expect(await harness.next() == "two")
        #expect(recognizer.calls.count == 2)
    }

    @Test("too little new audio since the last partial runs none, and the throttle tries again later")
    func waitsForNewAudio() async {
        var harness = Harness()
        harness.preview.begin()
        harness.preview.append(Self.audio(seconds: 1))
        await harness.tick(1)
        #expect(await harness.next() == "hello")

        harness.preview.append(Self.audio(seconds: 0.25))
        await harness.tick(2)
        await harness.clock.waitForSleeps(3)
        #expect(harness.recognizer.calls.count == 1)

        harness.preview.append(Self.audio(seconds: 0.25))
        harness.clock.advance(by: .seconds(1))
        #expect(await harness.next() == "hello")
        #expect(harness.recognizer.calls.count == 2)
    }

    @Test("only the newest window of audio is transcribed, and the word it cut in two is left out")
    func trailingWindow() async {
        var harness = Harness(recognizer: FakePartialRecognizer(answers: ["ito de la tarde"]))
        harness.preview.begin()
        harness.preview.append(Self.audio(seconds: 1, value: 0.1))
        harness.preview.append(Self.audio(seconds: 2, value: 0.2))
        await harness.tick(1)

        #expect(await harness.next() == "de la tarde")
        #expect(harness.recognizer.calls.map(\.clip) == [AudioClip(samples: Self.audio(seconds: 2, value: 0.2))])
    }

    @Test("a busy engine shows nothing new, and the next interval tries again")
    func busyEngine() async {
        var harness = Harness(recognizer: FakePartialRecognizer(answers: [nil, "later"]))
        harness.preview.begin()
        harness.preview.append(Self.audio(seconds: 1))
        await harness.tick(1)
        await harness.tick(2)

        #expect(await harness.next() == "later")
        #expect(harness.recognizer.calls.count == 2)
    }

    @Test("the end of the recording cancels the partial in flight, drops its text, and clears the preview")
    func endCancels() async {
        let recognizer = FakePartialRecognizer(answers: ["stale"], gated: true)
        var harness = Harness(recognizer: recognizer)
        harness.preview.begin()
        harness.preview.append(Self.audio(seconds: 1))
        await harness.tick(1)
        await recognizer.entered.wait()

        harness.preview.end()
        recognizer.release()

        #expect(await harness.next() == "")
        // The throttle stopped: no sleep follows, and audio after the end is not kept for anyone.
        harness.preview.append(Self.audio(seconds: 1))
        harness.clock.advance(by: .seconds(10))
        #expect(harness.clock.pendingSleeps == 0)
        #expect(recognizer.calls.count == 1)
    }

    @Test("a new recording starts from no audio, and a partial of the one before never shows in it")
    func newRecordingStartsClean() async {
        let recognizer = FakePartialRecognizer(answers: ["old", "new"], gated: true)
        var harness = Harness(recognizer: recognizer)
        harness.preview.begin()
        harness.preview.append(Self.audio(seconds: 1, value: 0.1))
        await harness.tick(1)
        await recognizer.entered.wait()
        harness.preview.end()
        #expect(await harness.next() == "")

        harness.preview.begin()
        recognizer.release()
        harness.preview.append(Self.audio(seconds: 1, value: 0.3))
        await harness.tick(2)
        await recognizer.entered.wait()
        recognizer.release()

        #expect(await harness.next() == "new")
        #expect(recognizer.calls.last?.clip == AudioClip(samples: Self.audio(seconds: 1, value: 0.3)))
    }

    @Test("with the preview off nothing is kept, timed, or transcribed")
    func disabled() async {
        let harness = Harness(enabled: false)
        harness.preview.begin()
        harness.preview.append(Self.audio(seconds: 3))
        harness.clock.advance(by: .seconds(10))
        harness.preview.end()

        #expect(harness.clock.suspendedSleeps == 0)
        #expect(harness.recognizer.calls.isEmpty)
    }

    /// A recognizer that also gives partials.
    private struct PartialCapable: SpeechRecognizer, PartialSpeechRecognizing {
        let id: ASRProviderID
        let locality: Locality
        let maxClipDuration: Duration? = nil
        func readiness() async -> RecognizerReadiness { .ready }
        func prepare() async {}
        func transcribe(_ clip: AudioClip, options: RecognitionOptions) async throws -> RawTranscript {
            RawTranscript(text: "final")
        }
        func transcribePartial(_ clip: AudioClip, language: String?) async throws -> String? { "partial" }
    }

    @Test("the registry gives partials from the selected recognizer only when it runs on this Mac and can")
    func registryPartials() {
        let settings = InMemorySettingsStore()
        let registry = RecognizerRegistry(
            providers: [
                PartialCapable(id: .parakeetV3, locality: .local), FakeRecognizer(id: ASRProviderID("plain")),
                PartialCapable(id: ASRProviderID("cloud"), locality: .cloud),
            ],
            settings: settings)

        #expect(registry.partialRecognizer() != nil)
        settings.set("plain", for: RecognitionSettings.provider)
        #expect(registry.partialRecognizer() == nil)
        settings.set("cloud", for: RecognitionSettings.provider)
        #expect(registry.partialRecognizer() == nil)
    }

    @Test("a recognizer that cannot give partials gets no work")
    func noPartialRecognizer() async {
        let harness = Harness(canTranscribe: false)
        harness.preview.begin()
        harness.preview.append(Self.audio(seconds: 3))
        harness.clock.advance(by: .seconds(10))

        #expect(harness.clock.suspendedSleeps == 0)
        #expect(harness.recognizer.calls.isEmpty)
    }
}
