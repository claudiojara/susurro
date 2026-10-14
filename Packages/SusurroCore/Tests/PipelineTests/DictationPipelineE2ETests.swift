import CoreTestSupport
import Domain
import Foundation
import Pipeline
import Synchronization
import Testing

/// The whole path, on fakes: a hold, the stored recording, voice detection, the recognizer, the history, the inserter.
@Suite("Durable dictation pipeline", .timeLimit(.minutes(1)))
struct DictationPipelineE2ETests {
    private typealias Harness = CoordinatorHarness
    private static let pressTime = DictationCoordinatorTests.pressTime

    /// A recognizer that notes what the history held at the moment it was called.
    private final class SpyRecognizer: SpeechRecognizer {
        let id = ASRProviderID.parakeetV3
        let locality = Locality.local
        let maxClipDuration: Duration? = nil
        private let history: InMemoryHistoryRepository
        private let seen = Mutex<[[DictationRecord]]>([])

        init(history: InMemoryHistoryRepository) {
            self.history = history
        }

        var recordsAtCall: [[DictationRecord]] { seen.withLock { $0 } }

        func readiness() async -> RecognizerReadiness { .ready }
        func prepare() async {}

        func transcribe(_ clip: AudioClip, options: RecognitionOptions) async throws -> RawTranscript {
            let records = (try? await history.page(offset: 0, limit: 10)) ?? []
            seen.withLock { $0.append(records) }
            return RawTranscript(text: "hola mundo")
        }
    }

    private static func record(_ h: Harness) async throws -> DictationRecord {
        try #require(try await h.history.page(offset: 0, limit: 10).first)
    }

    // MARK: The happy path

    @Test("a hold with speech reaches the inserter with the raw text, and the record says how it went")
    func holdToInsertedText() async throws {
        let speech = [SpeechSegment(start: .milliseconds(100), end: .milliseconds(900))]
        var h = await Harness(
            recognizer: FakeRecognizer(transcript: "hola mundo", id: .parakeetV3),
            vad: FakeVoiceActivityDetector(segments: speech))
        await h.startRecording()
        let states = await h.release()

        #expect(states == DictationCoordinatorTests.transcribed)
        #expect(h.inserter.insertedTexts == ["hola mundo"])
        let record = try await Self.record(h)
        #expect(record.status == .succeeded)
        #expect(record.rawText == "hola mundo")
        #expect(record.finalText == "hola mundo")
        #expect(record.asrProvider == .parakeetV3)
        #expect(record.delivery == .inserted)
        #expect(record.duration == .seconds(1))
        #expect(record.audioURL == FakeRecordingStore.url(for: SessionID(record.id)))
        #expect(record.failure == nil)
    }

    @Test("the recognizer hears the speech span of the stored recording: the voice, with room on each side")
    func recognizerHearsTheSpan() async throws {
        let speech = [SpeechSegment(start: .milliseconds(500), end: .milliseconds(600))]
        let recognizer = FakeRecognizer(transcript: "ok", id: .parakeetV3)
        var h = await Harness(recognizer: recognizer, vad: FakeVoiceActivityDetector(segments: speech))
        await h.startRecording(samples: DictationCoordinatorTests.audio(0.1, seconds: 2))
        _ = await h.release()

        // 0.5 s minus 450 ms of pre-roll to 0.6 s plus 450 ms of hangover, of a recording of 2 s.
        let heard = try #require(recognizer.transcribedClips.first)
        #expect(heard.duration == .milliseconds(1_000))
        // The stored file is whole.
        let stored = try #require(h.recordings.begun.first)
        #expect(h.recordings.samples(of: stored).count == 2 * AudioClip.sampleRate)
    }

    @Test("the record exists, with the audio, before the recognizer is called")
    func recordBeforeRecognizer() async throws {
        let history = InMemoryHistoryRepository()
        let spy = SpyRecognizer(history: history)
        let settings = InMemorySettingsStore()
        let recordings = FakeRecordingStore()
        let registry = RecognizerRegistry(providers: [spy], defaultProvider: spy.id, settings: settings)
        let sleeper = FakeSleeper()
        let sleep: @Sendable (Duration) async throws -> Void = { try await sleeper.sleep($0) }
        let pipeline = DictationPipeline(
            recordings: recordings, history: history, detector: FakeVoiceActivityDetector(),
            runner: RecognitionRunner(
                registry: registry, language: SettingsLanguagePreference(settings: settings), sleep: sleep),
            inserter: FakeTextInserter(), sleep: sleep)
        let recording = recordings.stored(AudioClip(samples: DictationCoordinatorTests.audio(0.1)))

        let result = await pipeline.process(DictationJob(recording: recording)) { _ in }

        #expect(result == .finished(.inserted))
        let atCall = try #require(spy.recordsAtCall.first)
        #expect(atCall.count == 1)
        #expect(atCall.first?.status == .processing)
        #expect(atCall.first?.id == recording.id.rawValue)
        #expect(atCall.first?.audioURL == recording.url)
    }

    @Test("with the default settings nothing is sent over the network")
    func defaultSendsNothing() async {
        let transport = SpyNetworkTransport()
        var h = await Harness(recognizer: FakeRecognizer(id: .parakeetV3, transport: transport))
        await h.startRecording()
        _ = await h.release()

        // The recognizer is local, so it never asks the transport: the spy would have seen the request.
        #expect(h.recognizer.locality == .local)
        #expect(transport.sent.isEmpty)
        #expect(h.inserter.insertedTexts.count == 1)
    }

    // MARK: No speech

    @Test("a recording with no speech ends as no speech, with a notice, and the recognizer is never called")
    func silentRoom() async throws {
        var h = await Harness(vad: FakeVoiceActivityDetector(segments: []))
        await h.startRecording(samples: DictationCoordinatorTests.audio(0.003))
        let states = await h.release()

        #expect(states == [.transcribing(progress: nil), .notice(.noSpeech), .idle])
        #expect(h.recognizer.transcribedClips.isEmpty)
        #expect(h.inserter.insertedTexts.isEmpty)
        let record = try await Self.record(h)
        #expect(record.status == .noSpeech)
        #expect(record.audioURL != nil)
    }

    @Test("a recording of all zeros reports a silent microphone")
    func mutedMicrophone() async throws {
        var h = await Harness(vad: FakeVoiceActivityDetector(segments: []))
        await h.startRecording(samples: DictationCoordinatorTests.audio(0))
        let states = await h.release()

        #expect(states == [.transcribing(progress: nil), .notice(.silentMicrophone), .idle])
        #expect(h.recognizer.transcribedClips.isEmpty)
        #expect(try await Self.record(h).status == .noSpeech)
    }

    @Test("a blank transcript ends as no speech, and the record keeps the blank text")
    func blankTranscript() async throws {
        var h = await Harness(recognizer: FakeRecognizer(transcript: "   "))
        await h.startRecording()
        let states = await h.release()

        #expect(states == [.transcribing(progress: nil), .notice(.noSpeech), .idle])
        #expect(h.inserter.insertedTexts.isEmpty)
        let record = try await Self.record(h)
        #expect(record.status == .noSpeech)
        #expect(record.finalText == nil)
    }

    @Test("a voice detector that fails does not lose the dictation")
    func detectorFailure() async throws {
        struct Failure: Error {}
        var h = await Harness(vad: FakeVoiceActivityDetector(failure: Failure()))
        await h.startRecording()
        let states = await h.release()

        #expect(states == DictationCoordinatorTests.transcribed)
        #expect(h.recognizer.transcribedClips == [AudioClip(samples: DictationCoordinatorTests.clip)])
        #expect(h.diagnostics.events == [.voiceDetectionFailed])
    }

    // MARK: Discards

    @Test("a tap and a recording under 300 ms leave no job and no history record", arguments: [0, 100, 299])
    func shortHold(heldMilliseconds: Int) async throws {
        var h = await Harness()
        await h.startRecording()
        let states = await h.release(after: heldMilliseconds)

        #expect(states == [.idle])
        #expect(try await h.history.page(offset: 0, limit: 10).isEmpty)
        #expect(h.recognizer.transcribedClips.isEmpty)
        #expect(h.recordings.aborted == h.recordings.begun)
    }

    @Test("a recording of 200 ms of audio is discarded even when the key was held longer")
    func shortAudio() async throws {
        var h = await Harness()
        await h.startRecording(samples: DictationCoordinatorTests.audio(0.1, seconds: 0.2))
        let states = await h.release()

        #expect(states == [.idle])
        #expect(try await h.history.page(offset: 0, limit: 10).isEmpty)
        #expect(h.recognizer.transcribedClips.isEmpty)
    }

    // MARK: Failures

    @Test("a transcription that times out is a failed record with its audio, and an error")
    func transcriptionTimeout() async throws {
        let sleeper = FakeSleeper(expiring: [DictationLimits.transcriptionTimeout])
        var h = await Harness(recognizer: FakeRecognizer(gated: true), sleeper: sleeper)
        await h.startRecording()
        let states = await h.release()

        #expect(states == [.transcribing(progress: nil), .error(.timedOut(.transcription)), .idle])
        let record = try await Self.record(h)
        #expect(record.status == .failed)
        #expect(record.failure == "timedOut.transcription")
        #expect(record.audioURL != nil)
        #expect(h.recordings.aborted.isEmpty)
    }

    @Test("a recognizer that fails is a failed record named by the kind of error, never its text")
    func recognizerFailure() async throws {
        struct Quote: Error, CustomStringConvertible { let description = "the user said hunter2" }
        var h = await Harness(recognizer: FakeRecognizer(failure: Quote()))
        await h.startRecording()
        _ = await h.release()

        let record = try await Self.record(h)
        #expect(record.status == .failed)
        #expect(record.failure == "recognitionFailed")
    }

    @Test("a transcript the inserter reports as not inserted stays in the record, so the history can give it back")
    func notInsertedKeepsTheText() async throws {
        let inserter = FakeTextInserter(outcome: .notInserted(.clipboardChanged))
        var h = await Harness(recognizer: FakeRecognizer(transcript: "se perdió"), inserter: inserter)
        await h.startRecording()
        let states = await h.release()

        #expect(states == [.transcribing(progress: nil), .error(.notInserted(.clipboardChanged)), .idle])
        let record = try await Self.record(h)
        #expect(record.status == .succeeded)
        #expect(record.finalText == "se perdió")
        #expect(record.delivery == .notInserted)
    }

    @Test("text left on the clipboard is recorded as copied")
    func copiedDelivery() async throws {
        let inserter = FakeTextInserter(outcome: .copiedToClipboard(.accessibilityMissing))
        var h = await Harness(inserter: inserter)
        await h.startRecording()
        _ = await h.release()

        #expect(try await Self.record(h).delivery == .copiedToClipboard)
    }

    @Test("a history that cannot be written is logged, and the dictation still goes in")
    func historyFailure() async {
        let history = InMemoryHistoryRepository()
        history.failAllCalls(with: HistoryError.recordNotFound(UUID()))
        var h = await Harness(history: history)
        await h.startRecording()
        let states = await h.release()

        #expect(states == DictationCoordinatorTests.transcribed)
        #expect(h.inserter.insertedTexts == ["hello"])
        #expect(h.diagnostics.events == [.historyWriteFailed(step: "insert")])
    }

    @Test("a recording that cannot be read back ends in a persistence error and the recognizer is never invoked")
    func unreadableRecording() async throws {
        let recordings = FakeRecordingStore(.init(loadFails: true))
        var h = await Harness(recordings: recordings)
        await h.startRecording()
        let states = await h.release()

        #expect(
            states == [
                .transcribing(progress: nil), .error(.persistenceFailed("the recording could not be read back")), .idle,
            ])
        #expect(h.recognizer.transcribedClips.isEmpty)
        let record = try await Self.record(h)
        #expect(record.status == .failed)
        #expect(record.failure == "persistenceFailed")
    }
}
