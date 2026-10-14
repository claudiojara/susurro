import CoreTestSupport
import Domain
import Foundation
import Pipeline
import Testing

@Suite("Whole clip reprocessor", .timeLimit(.minutes(1)))
struct WholeClipReprocessorTests {
    private let clip = AudioClip(samples: [0.1, 0.2, 0.3])
    private let clock = ManualClock()
    private let record = DictationRecord(createdAt: Date(timeIntervalSince1970: 1_800_000_000), duration: .seconds(3))

    private func makeReprocessor(_ recognizer: FakeRecognizer) -> WholeClipReprocessor {
        let clock = clock
        return WholeClipReprocessor(
            recognizer: recognizer, providerID: ASRProviderID("parakeet-v3"), sleep: { try await clock.sleep(for: $0) })
    }

    @Test("the whole clip goes to the recognizer and its transcript is the raw and the final text")
    func transcribes() async throws {
        let recognizer = FakeRecognizer(transcript: "  hola mundo \n")

        let outcome = try await makeReprocessor(recognizer).reprocess(clip, for: record)

        #expect(
            outcome
                == .text(
                    ReprocessedText(rawText: "hola mundo", finalText: "hola mundo", asrProvider: ASRProviderID("parakeet-v3"))))
        #expect(recognizer.transcribedClips == [clip])
    }

    @Test("a blank transcript is no speech")
    func blankIsNoSpeech() async throws {
        let outcome = try await makeReprocessor(FakeRecognizer(transcript: "   ")).reprocess(clip, for: record)

        #expect(outcome == .noSpeech)
    }

    @Test(
        "a recognizer that is not ready fails with the error that names why, and transcribes nothing",
        arguments: [
            (RecognizerReadiness.notInstalled, PipelineError.recognizerNotInstalled),
            (.loading(progress: 0.4), .recognizerUnavailable("The speech model is still loading.", retryable: true)),
            (.unavailable("disk full", retryable: false), .recognizerUnavailable("disk full", retryable: false)),
        ])
    func notReady(readiness: RecognizerReadiness, error: PipelineError) async {
        let recognizer = FakeRecognizer(readiness: [readiness])

        await #expect(throws: error) { try await makeReprocessor(recognizer).reprocess(clip, for: record) }
        #expect(recognizer.transcribedClips.isEmpty)
    }

    @Test("a recognizer that fails gives a recognition failure that names the error kind and no text")
    func recognizerFails() async {
        let recognizer = FakeRecognizer(failure: RecognitionError.engineFailed("boom"))

        await #expect(throws: PipelineError.self) { try await makeReprocessor(recognizer).reprocess(clip, for: record) }
    }

    @Test("a transcription that takes too long is abandoned with a timeout")
    func timesOut() async {
        let recognizer = FakeRecognizer(gated: true)
        let reprocessor = makeReprocessor(recognizer)
        let clock = clock

        let task = Task { try await reprocessor.reprocess(clip, for: record) }
        await clock.waitForSleeps(1)
        clock.advance(by: DictationLimits.transcriptionTimeout)

        await #expect(throws: PipelineError.timedOut(.transcription)) { try await task.value }
    }
}
