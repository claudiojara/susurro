import AVFoundation
import AppleIntelligenceCleaner
import AudioIO
import CoreTestSupport
import Domain
import FluidAudioASR
import Foundation
import Persistence
import Pipeline
import Synchronization
import Testing
import TextShaping

/// The speech path with the real models, from a recording file to the text that reaches the inserter. Run them with
/// `SUSURRO_REAL_MODELS=1` (see `Trait.realModels`).
@Suite("Real models through the pipeline", .realModels, .serialized, .timeLimit(.minutes(15)))
struct RealPipelineTests {
    /// About five seconds of Spanish at the pace of the Paulina voice.
    private static let fiveSeconds = "Hola, quería confirmar la reunión de mañana a las diez con el equipo de ventas."
    private static let sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    // MARK: Support

    private static func scratchFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "susurro-real-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Writes `samples` the way a recording is written, in chunks of the size a capture delivers, and returns the sink
    /// that is still open: closing it is what the release of the key does.
    private static func write(_ samples: [Float], to store: CAFRecordingStore) async throws -> any AudioRecordingSink {
        let sink = try await store.begin(SessionID())
        var start = 0
        while start < samples.count {
            let end = min(start + 4_096, samples.count)
            try await sink.append(AudioChunk(samples: Array(samples[start..<end])))
            start = end
        }
        return sink
    }

    /// The parakeet model, loaded.
    private static func loadedParakeet() async throws -> ParakeetRecognizer {
        let recognizer = ParakeetRecognizer()
        await recognizer.prepare()
        for await readiness in await recognizer.readinessChanges() {
            if readiness == .ready { return recognizer }
            if case .unavailable(let reason, _) = readiness { throw Failure(reason: reason) }
        }
        throw Failure(reason: "the readiness stream ended")
    }

    private struct Failure: Error, CustomStringConvertible {
        let reason: String
        var description: String { reason }
    }

    private static func seconds(_ segments: [SpeechSegment]) -> String {
        segments.map {
            "\($0.start.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 2))))-\($0.end.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 2))))"
        }
        .joined(separator: ", ")
    }

    // MARK: 3c.6 Silero on a recorded CAF

    @Test("Silero finds the speech in a recording that the app's store wrote as a CAF, and none in silence or noise")
    func sileroOnRecordedCAF() async throws {
        let folder = try Self.scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CAFRecordingStore(directory: { folder })
        let speech = try SpokenClip.speak(Self.fiveSeconds)
        let lead = 1.5
        let samples = SpokenClip.silence(seconds: lead) + speech + SpokenClip.silence(seconds: 1.5)
        let detector = SileroVADDetector()

        let recording = try await Self.write(samples, to: store).finish()
        let bytes = try #require(
            try FileManager.default.attributesOfItem(atPath: recording.url.path)[.size] as? Int)
        let fromFile = try await CAFClipLoader().clip(at: recording.url)
        let fromStore = try await store.load(recording)
        let heard = try await detector.analyze(fromFile)
        let direct = try await detector.analyze(AudioClip(samples: samples))
        print(
            "REAL-WORLD 3c.6 CAF \(recording.url.pathExtension), \(bytes) bytes, \(fromFile.samples.count) samples (\(SpokenClip.seconds(samples)) s written): silero on the file: [\(Self.seconds(heard.segments))], on the same samples in memory: [\(Self.seconds(direct.segments))], speech spoken at \(lead)-\(lead + SpokenClip.seconds(speech)) s"
        )

        #expect(fromFile == fromStore)
        #expect(abs(fromFile.samples.count - samples.count) <= 160)
        let first = try #require(heard.segments.first)
        let last = try #require(heard.segments.last)
        // The model decides in blocks of 256 ms, so the edges are only as exact as that.
        #expect(first.start > .seconds(lead - 0.5) && first.start < .seconds(lead + 0.6))
        #expect(last.end > .seconds(lead + SpokenClip.seconds(speech) - 0.6))
        #expect(last.end < .seconds(lead + SpokenClip.seconds(speech) + 0.9))
        // The 16-bit file costs the model nothing: the segments are those of the same samples in memory.
        #expect(heard.segments.count == direct.segments.count)
        for (a, b) in zip(heard.segments, direct.segments) {
            #expect(abs((a.start - b.start) / .seconds(1)) < 0.1 && abs((a.end - b.end) / .seconds(1)) < 0.1)
        }

        for (name, quiet) in [
            ("silence", SpokenClip.silence(seconds: 4)),
            ("room noise", (0..<4 * SpokenClip.sampleRate).map { _ in Float.random(in: -0.003...0.003) }),
        ] {
            let silent = try await Self.write(quiet, to: store).finish()
            let result = try await detector.analyze(try await CAFClipLoader().clip(at: silent.url))
            print("REAL-WORLD 3c.6 \(name) CAF: segments [\(Self.seconds(result.segments))]")
            #expect(result.segments.isEmpty)
        }
    }

    // MARK: 4d.10 Release to text

    /// Notes when the text reached it.
    private final class TimedInserter: TextInserter {
        private let reached = Mutex<(text: String, at: ContinuousClock.Instant)?>(nil)
        var last: (text: String, at: ContinuousClock.Instant)? { reached.withLock { $0 } }

        func insert(_ text: String) async -> InsertionOutcome {
            reached.withLock { $0 = (text, .now) }
            return .inserted
        }

        func drain() async {}
    }

    /// Measures how long a stage takes, and passes the call on.
    private final class Stopwatch: Sendable {
        private let spans = Mutex<[Duration]>([])
        var lastSpan: Duration { spans.withLock { $0.last ?? .zero } }

        func measure<T>(_ work: () async throws -> T) async rethrows -> T {
            let started = ContinuousClock.now
            defer { spans.withLock { $0.append(ContinuousClock.now - started) } }
            return try await work()
        }
    }

    private struct TimedDetector: VoiceActivityDetector {
        let base: any VoiceActivityDetector
        let watch: Stopwatch
        func analyze(_ clip: AudioClip) async throws -> VADResult {
            try await watch.measure { try await base.analyze(clip) }
        }
    }

    private struct TimedRecognizer: SpeechRecognizer {
        let base: ParakeetRecognizer
        let watch: Stopwatch
        var id: ASRProviderID { base.id }
        var locality: Locality { base.locality }
        var maxClipDuration: Duration? { base.maxClipDuration }
        func readiness() async -> RecognizerReadiness { await base.readiness() }
        func prepare() async { await base.prepare() }
        func transcribe(_ clip: AudioClip, options: RecognitionOptions) async throws -> RawTranscript {
            try await watch.measure { try await base.transcribe(clip, options: options) }
        }
    }

    /// One dictation of `samples` from the release of the key to the text at the inserter, over `count` runs.
    private struct Run {
        let release: Duration
        let finish: Duration
        let voice: Duration
        let speech: Duration
        let rest: Duration
        /// What the cleanup stage did, from the history record: the cleaner and why it fell back, if it did.
        let cleanup: String
        let text: String
    }

    private static func dictate(
        _ samples: [Float], runs count: Int, cleaner: (any TranscriptCleaner)?, in folder: URL
    ) async throws -> (runs: [Run], history: GRDBHistoryRepository, recordings: [VerifiedRecording]) {
        let parakeet = try await loadedParakeet()
        let settings = InMemorySettingsStore()
        let voiceWatch = Stopwatch()
        let speechWatch = Stopwatch()
        let registry = RecognizerRegistry(
            providers: [TimedRecognizer(base: parakeet, watch: speechWatch)], settings: settings)
        let store = CAFRecordingStore(directory: { folder.appending(path: "Audio") })
        let history = try GRDBHistoryRepository(path: folder.appending(path: "history.sqlite").path)
        let inserter = TimedInserter()
        let stage = cleaner.map { cleaner in
            CleanupStage(isEnabled: { true }, cleaner: { cleaner }, sleep: Self.sleep)
        }
        let pipeline = DictationPipeline(
            recordings: store, history: history,
            detector: TimedDetector(base: SileroVADDetector(), watch: voiceWatch),
            runner: RecognitionRunner(
                registry: registry, language: SettingsLanguagePreference(settings: settings), sleep: Self.sleep),
            inserter: inserter, cleanup: stage, sleep: Self.sleep)

        var runs: [Run] = []
        var recordings: [VerifiedRecording] = []
        for _ in 0..<count {
            // The recording is written as the user speaks; the clock starts when the key comes up.
            let sink = try await Self.write(samples, to: store)
            let released = ContinuousClock.now
            let recording = try await sink.finish()
            let closed = ContinuousClock.now
            let result = await pipeline.process(DictationJob(recording: recording)) { _ in }
            let inserted = try #require(inserter.last)
            try #require(result == .finished(.inserted), "the dictation ended as \(result)")
            let release = inserted.at - released
            let voice = voiceWatch.lastSpan
            let speech = speechWatch.lastSpan
            let record = try await history.record(id: recording.id.rawValue)
            let cleanup = record.map {
                "\($0.cleanerProvider ?? "no cleaner"), fallback \($0.fallbackReason ?? "none")"
            }
            runs.append(
                Run(
                    release: release, finish: closed - released, voice: voice, speech: speech,
                    rest: release - (closed - released) - voice - speech, cleanup: cleanup ?? "no record",
                    text: inserted.text))
            recordings.append(recording)
        }
        return (runs, history, recordings)
    }

    private static func report(_ label: String, _ runs: [Run]) {
        for (index, run) in runs.enumerated() {
            print(
                "REAL-WORLD 4d.10 \(label) run \(index + 1): release to text \(Int(run.release.milliseconds)) ms = close and verify the CAF \(Int(run.finish.milliseconds)) + Silero \(Int(run.voice.milliseconds)) + Parakeet \(Int(run.speech.milliseconds)) + the rest \(Int(run.rest.milliseconds)) (\(run.cleanup)); \"\(run.text)\""
            )
        }
    }

    @Test(
        "a 5 s Spanish dictation reaches the inserter in under 2 s after the release, and the file and the record exist"
    )
    func releaseToText() async throws {
        let folder = try Self.scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let speech = try SpokenClip.speak(Self.fiveSeconds)
        let samples = SpokenClip.silence(seconds: 0.3) + speech + SpokenClip.silence(seconds: 0.3)
        try #require(SpokenClip.seconds(samples) > 4.5 && SpokenClip.seconds(samples) < 6.5)

        let (runs, history, recordings) = try await Self.dictate(samples, runs: 6, cleaner: nil, in: folder)
        print(
            "REAL-WORLD 4d.10 clip of \(SpokenClip.seconds(samples)) s, no cleanup (the raw transcript is inserted); the first run is the first dictation after the models load"
        )
        Self.report("raw", runs)

        let warm = runs.dropFirst()
        let median = warm.map(\.release).sorted()[warm.count / 2]
        print(
            "REAL-WORLD 4d.10 raw: first run \(Int(runs[0].release.milliseconds)) ms, warm runs median \(Int(median.milliseconds)) ms, worst \(Int((warm.map(\.release).max() ?? .zero).milliseconds)) ms"
        )
        for run in runs {
            #expect(run.release < .seconds(2))
            let words = SpokenClip.words(run.text)
            // Parakeet writes the hour as numerals.
            #expect(words.contains("reunion") && (words.contains("diez") || run.text.contains("10")))
            #expect(words.contains("ventas"))
        }

        // The stored file and the history row of the last dictation.
        let recording = try #require(recordings.last)
        #expect(FileManager.default.fileExists(atPath: recording.url.path))
        let record = try #require(try await history.record(id: recording.id.rawValue))
        #expect(record.status == .succeeded)
        #expect(record.audioURL == recording.url)
        #expect(record.asrProvider == .parakeetV3)
        #expect(record.rawText == runs.last?.text && record.finalText == runs.last?.text)
        print(
            "REAL-WORLD 4d.10 history row \(record.id): status \(record.status), asr \(record.asrProvider?.rawValue ?? "-"), delivery \(String(describing: record.delivery)), audio \(recording.url.lastPathComponent) exists"
        )
    }

    @Test("with Apple Intelligence cleanup on, which is the default, the same dictation takes this long")
    func releaseToTextWithCleanup() async throws {
        let cleaner = AppleIntelligenceCleaner()
        guard await cleaner.availability() == .available else {
            try Test.cancel("Apple Intelligence is not available.")
        }
        let folder = try Self.scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let speech = try SpokenClip.speak(Self.fiveSeconds)
        let samples = SpokenClip.silence(seconds: 0.3) + speech + SpokenClip.silence(seconds: 0.3)

        let (runs, _, _) = try await Self.dictate(samples, runs: 4, cleaner: cleaner, in: folder)
        Self.report("with cleanup", runs)

        // No bound is asserted: this is the number that the 2 s of the proposal has to be read against.
        #expect(runs.allSatisfy { !$0.text.isEmpty })
    }

    // MARK: 8a.9 A dictionary term

    @Test(
        "a dictionary term does not change what Parakeet writes: the speech spec lets a recognizer without biasing ignore it"
    )
    func parakeetIgnoresTheTerm() async throws {
        let parakeet = try await Self.loadedParakeet()
        let term = "Kaelthorn"
        let speech = try SpokenClip.speak("Mañana tengo una reunión con Kaelthorn para revisar el contrato.")
        let clip = AudioClip(samples: SpokenClip.silence(seconds: 0.3) + speech + SpokenClip.silence(seconds: 0.3))

        let plain = try await parakeet.transcribe(clip, options: RecognitionOptions(language: "es")).text
        let hinted = try await parakeet.transcribe(
            clip, options: RecognitionOptions(language: "es", vocabulary: [term])
        ).text
        let crowded = try await parakeet.transcribe(
            clip, options: RecognitionOptions(language: "es", vocabulary: [term] + (1...49).map { "Término \($0)" })
        ).text
        print(
            "REAL-WORLD 8a.9 Parakeet without the term: \"\(plain)\"; with it: \"\(hinted)\"; with it among 50: \"\(crowded)\""
        )

        // The clip is one the model gets wrong without help, and the term does not help it.
        #expect(!plain.contains(term))
        #expect(hinted == plain && crowded == plain)
    }

    @Test("a dictionary term reaches the final text only when the cleaner fixes a near miss with it")
    func cleanerUsesTheTerm() async throws {
        let cleaner = AppleIntelligenceCleaner()
        guard await cleaner.availability() == .available else {
            try Test.cancel("Apple Intelligence is not available.")
        }
        let style = StyleProfile(category: .document, tone: .neutral, source: .bundle)
        // What a recognizer writes for a name it does not know: the sounds, spelled the usual way.
        let raw = "hablé con maría gonzales sobre el pedido"
        let term = "María González"
        var finals: [String] = []
        for vocabulary in [[], [term]] {
            let request = LocalCleanupRequest(transcript: raw, style: style, vocabulary: vocabulary, beforeCursor: "")
            let output = try await cleaner.clean(.local(request))
            switch OutputGuard.evaluate(raw: raw, output: output, reference: vocabulary) {
            case .accepted(let text): finals.append(text)
            case .fallback(let reason): finals.append("(raw, \(reason)) \(raw)")
            }
        }
        print("REAL-WORLD 8a.9 cleaner without the term: \"\(finals[0])\"; with it: \"\(finals[1])\"")

        #expect(finals[1].contains("González"))
        #expect(!finals[0].contains("González"))
    }
}
