import CoreTestSupport
import Domain
import Testing

@testable import Pipeline

/// The coordinator feeds the live preview the audio of the recording, and ends it the moment the recording ends, before
/// the transcript that is pasted is asked for.
@Suite("Dictation coordinator: live preview", .timeLimit(.minutes(1)))
struct DictationCoordinatorPreviewTests {
    private static let policy = LiveTranscriptPreview.Policy(
        interval: .seconds(1), window: .seconds(12), minimumNewAudio: .milliseconds(500))

    @Test("the preview hears the recording, and the key-up ends it before the dictation is transcribed")
    func previewFollowsTheRecording() async throws {
        let clock = ManualClock()
        let partial = FakePartialRecognizer(answers: ["hel", "stale"], gated: true)
        let preview = LiveTranscriptPreview(
            policy: Self.policy, clock: clock, isEnabled: { true }, recognizer: { partial }, language: { nil })
        var partials = preview.partials.makeAsyncIterator()
        var harness = await CoordinatorHarness(preview: preview)

        await harness.startRecording()
        await clock.waitForSleeps(1)
        clock.advance(by: .seconds(1))
        await partial.entered.wait()
        partial.release()
        #expect(await partials.next() == "hel")
        #expect(partial.calls.map(\.clip) == [AudioClip(samples: DictationCoordinatorTests.clip)])

        await clock.waitForSleeps(2)
        // Less than the rest of the cap, so that the key and not the cap ends the recording, and louder, so that its
        // level says when it has arrived.
        var levels = harness.sut.levels.makeAsyncIterator()
        let first = await levels.next()
        harness.capture.emit(AudioChunk(samples: [Float](repeating: 0.3, count: 9_600)))
        while await levels.next() == first {}
        clock.advance(by: .seconds(1))
        await partial.entered.wait()
        await harness.sut.handle(.up(at: DictationCoordinatorTests.pressTime + .milliseconds(1200)))
        #expect(await partials.next() == "")
        partial.release()

        #expect(await harness.read(through: .idle) == DictationCoordinatorTests.transcribed)
        #expect(harness.inserter.insertedTexts == ["hello"])
    }

    @Test("a recording that could not start leaves no preview running")
    func failedStartEndsThePreview() async throws {
        let clock = ManualClock()
        let partial = FakePartialRecognizer()
        let preview = LiveTranscriptPreview(
            policy: Self.policy, clock: clock, isEnabled: { true }, recognizer: { partial }, language: { nil })
        var partials = preview.partials.makeAsyncIterator()
        let harness = await CoordinatorHarness(
            capture: FakeAudioCaptureSource(startFailure: CaptureError.noInputDevice), preview: preview)

        await harness.sut.handle(.down(at: DictationCoordinatorTests.pressTime))

        #expect(await partials.next() == "")
        clock.advance(by: .seconds(5))
        #expect(partial.calls.isEmpty)
    }
}
