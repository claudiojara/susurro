import CoreTestSupport
import Domain
import Pipeline
import Testing

@Suite("Pasting after a hold that ran into the recording cap", .timeLimit(.minutes(1)))
struct CapReleaseWaitTests {
    private typealias Harness = CoordinatorHarness
    private static let pressTime = DictationCoordinatorTests.pressTime
    private static let afterTheCap = pressTime + .seconds(61)
    private static let upToTheTranscription: [PipelineState] = [
        .starting, .recording(.hold), .notice(.capReached), .transcribing(progress: nil),
    ]

    /// Presses and holds the key until the cap finishes the recording. Returns the states up to the transcription.
    private static func holdUntilTheCap(_ h: inout Harness) async -> [PipelineState] {
        await h.sut.handle(.down(at: pressTime))
        h.capture.emit(AudioChunk(samples: [Float](repeating: 0.5, count: DictationCoordinatorTests.capSamples)))
        return await h.read(through: .transcribing(progress: nil))
    }

    @Test("the release limit is about ten seconds, and apart from the other limits that a sleeper can expire")
    func limitIsInRange() {
        #expect(DictationLimits.releaseWaitTimeout >= .seconds(5))
        #expect(DictationLimits.releaseWaitTimeout <= .seconds(15))
        // The tests expire one deadline by its length, so the release limit must differ from every other.
        let others = [
            DictationLimits.insertionTimeout, DictationLimits.transcriptionTimeout,
            DictationLimits.captureStartTimeout, DictationLimits.captureStopTimeout,
            DictationLimits.prepareTimeout, DictationLimits.drainTimeout,
        ]
        #expect(!others.contains(DictationLimits.releaseWaitTimeout))
    }

    @Test("with the key still down at the cap, nothing is inserted until the release, and then the text goes in")
    func insertsAfterTheRelease() async {
        var h = await Harness(recognizer: FakeRecognizer(transcript: "hola"))
        let started = await Self.holdUntilTheCap(&h)
        await h.sleeper.entered(DictationLimits.releaseWaitTimeout).wait()  // the transcription is done
        let insertedWhileHeld = h.inserter.insertedTexts
        let rest = await h.release(after: 61_000)

        #expect(started == Self.upToTheTranscription)
        #expect(insertedWhileHeld.isEmpty)
        #expect(rest == [.inserted, .idle])
        #expect(h.inserter.insertedTexts == ["hola"])
        #expect(h.recognizer.transcribedClips.count == 1)
        #expect(h.diagnostics.events == [.recordingCapReached])
    }

    @Test("a release before the transcription ends lets the text in as soon as it is ready")
    func releaseBeforeTheTranscriptionEnds() async {
        var h = await Harness(recognizer: FakeRecognizer(transcript: "hola", gated: true))
        _ = await Self.holdUntilTheCap(&h)
        await h.recognizer.transcribeEntered.wait()
        await h.sut.handle(.up(at: Self.afterTheCap))
        let insertedBeforeTheText = h.inserter.insertedTexts
        h.recognizer.releaseTranscription()

        // No deadline is ever fired in this test: an insertion that waited for the limit would never happen.
        #expect(await h.read(through: .idle) == [.inserted, .idle])
        #expect(insertedBeforeTheText.isEmpty)
        #expect(h.inserter.insertedTexts == ["hola"])
    }

    @Test("a key that is never released holds the text back for the limit and no longer, and it goes in once")
    func insertsAfterTheLimit() async {
        var h = await Harness(recognizer: FakeRecognizer(transcript: "hola"))
        _ = await Self.holdUntilTheCap(&h)
        await h.sleeper.entered(DictationLimits.releaseWaitTimeout).wait()
        let insertedBeforeTheLimit = h.inserter.insertedTexts
        h.sleeper.fire(DictationLimits.releaseWaitTimeout)
        let rest = await h.read(through: .idle)
        await h.sut.handle(.up(at: Self.afterTheCap))  // the release that comes too late does nothing

        #expect(insertedBeforeTheLimit.isEmpty)
        #expect(rest == [.inserted, .idle])
        #expect(h.inserter.insertedTexts == ["hola"])
        #expect(h.capture.startCount == 1)
        #expect(h.diagnostics.events == [.recordingCapReached, .releaseWaitExpired])
    }

    @Test(
        "a new press during the wait takes the old key as released, so the text goes in without waiting for the limit")
    func pressDuringTheWait() async {
        var h = await Harness(recognizer: FakeRecognizer(transcript: "hola"))
        _ = await Self.holdUntilTheCap(&h)
        await h.sleeper.entered(DictationLimits.releaseWaitTimeout).wait()
        await h.sut.handle(.down(at: Self.afterTheCap))
        let rest = await h.read(through: .inserted)

        // The release limit is never fired in this test: the text did not wait for it.
        #expect(rest.last == .inserted)
        #expect(h.inserter.insertedTexts == ["hola"])
        #expect(h.capture.startCount == 2)
    }

    @Test("shutting down during the wait inserts nothing")
    func shutdownDuringTheWait() async {
        var h = await Harness()
        _ = await Self.holdUntilTheCap(&h)
        await h.sleeper.entered(DictationLimits.releaseWaitTimeout).wait()
        await h.sut.shutdown()

        #expect(h.inserter.insertedTexts.isEmpty)
        #expect(await h.read(through: .idle) == [.idle])
    }

    @Test("a hold that ends with the release is inserted at once, without any wait for the key")
    func ordinaryReleaseDoesNotWait() async {
        var h = await Harness()
        await h.startRecording()

        // The release limit is never fired in this test, so a wait for the key would hang it.
        #expect(await h.release() == DictationCoordinatorTests.transcribed)
        #expect(h.diagnostics.events.isEmpty)
    }

    @Test("a hold that ran into the cap and was released while the capture stops is inserted at once")
    func releaseWhileTheCaptureStops() async {
        let capture = FakeAudioCaptureSource(onStop: .holdStreamOpen)
        var h = await Harness(capture: capture)
        await h.sut.handle(.down(at: Self.pressTime))
        capture.emit(AudioChunk(samples: [Float](repeating: 0.5, count: DictationCoordinatorTests.capSamples)))
        await capture.stopped.wait()  // the recording is finishing: the stop has returned, the stream is still open
        await h.sut.handle(.up(at: Self.afterTheCap))
        capture.finish()

        // The release limit is never fired in this test, so a wait for the key would hang it.
        #expect(
            await h.read(through: .idle)
                == [.starting, .recording(.hold), .notice(.capReached)] + DictationCoordinatorTests.transcribed)
        #expect(h.inserter.insertedTexts == ["hello"])
    }
}
