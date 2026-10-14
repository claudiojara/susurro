import CoreTestSupport
import Domain
import Foundation
import Pipeline
import Synchronization
import Testing

@Suite("Transcription timeout", .timeLimit(.minutes(1)))
struct TranscriptionTimeoutTests {
    /// A long clip: 400 s, so that a tenth of it is longer than the floor of the limit.
    private static let longClip = AudioClip(samples: [Float](repeating: 0.1, count: 400 * AudioClip.sampleRate))

    /// The durations that the code under test asked to sleep, which its deadlines are.
    private final class Sleeps: Sendable {
        private let asked = Mutex<[Duration]>([])
        var durations: [Duration] { asked.withLock { $0 } }
        func record(_ duration: Duration) { asked.withLock { $0.append(duration) } }
    }

    @Test(
        "the limit is 30 s for a clip of up to five minutes, and a tenth of the clip beyond",
        arguments: [(1, 30), (60, 30), (300, 30), (400, 40), (600, 60)])
    func limit(clipSeconds: Int, limitSeconds: Int) {
        #expect(DictationLimits.transcriptionTimeout(forClip: .seconds(clipSeconds)) == .seconds(limitSeconds))
    }

    @Test("the runner bounds the call to the recognizer by the length of the clip")
    func runnerScalesTheLimit() async throws {
        let clock = ManualClock()
        let sleeps = Sleeps()
        let recognizer = FakeRecognizer(transcript: "hola", gated: true)
        let settings = InMemorySettingsStore()
        let runner = RecognitionRunner(
            registry: RecognizerRegistry(providers: [recognizer], defaultProvider: recognizer.id, settings: settings),
            language: SettingsLanguagePreference(settings: settings),
            sleep: { duration in
                sleeps.record(duration)
                try await clock.sleep(for: duration)
            })

        let work = Task { try await runner.run(Self.longClip, progress: { _ in }) }
        await recognizer.transcribeEntered.wait()
        await clock.waitForSleeps(1)
        recognizer.releaseTranscription()
        let outcome = try await work.value

        #expect(outcome.text == "hola")
        #expect(sleeps.durations == [.seconds(40)])
    }

    @Test("the reprocessor bounds the call to the recognizer by the length of the clip")
    func reprocessorScalesTheLimit() async throws {
        let clock = ManualClock()
        let sleeps = Sleeps()
        let recognizer = FakeRecognizer(transcript: "hola", gated: true)
        let reprocessor = WholeClipReprocessor(
            recognizer: recognizer,
            sleep: { duration in
                sleeps.record(duration)
                try await clock.sleep(for: duration)
            })
        let record = DictationRecord(createdAt: Date(timeIntervalSince1970: 1_800_000_000), duration: .seconds(400))

        let work = Task { try await reprocessor.reprocess(Self.longClip, for: record) }
        await recognizer.transcribeEntered.wait()
        await clock.waitForSleeps(1)
        recognizer.releaseTranscription()
        _ = try await work.value

        #expect(sleeps.durations == [.seconds(40)])
    }
}
