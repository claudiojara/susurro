import CoreTestSupport
import Domain
import Testing

@testable import FluidAudioASR

@Suite("Parakeet cancellation", .timeLimit(.minutes(1)))
struct ParakeetCancellationTests {
    @Test("cancelling a transcription in the engine ends it with a cancellation, not a recognition error")
    func cancellationReachesTheEngine() async {
        let engine = FakeParakeetEngine(gatedTranscription: true)
        let recognizer = await ParakeetRecognizer.ready(engine: engine)
        let clip = AudioClip.ramp(samples: engine.minimumSampleCount)
        let task = Task { try await recognizer.transcribe(clip, options: RecognitionOptions()) }
        await engine.entered.wait()

        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(engine.transcriptions.count == 1)
    }

    @Test("a transcription that starts cancelled never reaches the engine")
    func cancelledBeforeTheEngine() async {
        let engine = FakeParakeetEngine()
        let recognizer = await ParakeetRecognizer.ready(engine: engine)
        let clip = AudioClip.ramp(samples: engine.minimumSampleCount)
        let start = Gate()
        let task = Task {
            await start.wait()
            return try await recognizer.transcribe(clip, options: RecognitionOptions())
        }

        task.cancel()
        start.open()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(engine.transcriptions.isEmpty)
    }
}
