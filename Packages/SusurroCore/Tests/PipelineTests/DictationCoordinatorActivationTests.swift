import CoreTestSupport
import Domain
import Pipeline
import Testing

extension CoordinatorHarness {
    static var pressTime: Duration { DictationCoordinatorTests.pressTime }

    /// Taps (a short press that records a little audio and is discarded), presses again inside the window, and waits for
    /// the hands-free recording. The second key is released again, as a finger would.
    mutating func startHandsFree(samples: [Float] = DictationCoordinatorTests.clip) async {
        await startRecording()
        await sut.handle(.up(at: Self.pressTime + .milliseconds(80)))
        _ = await read(through: .idle)
        await sut.handle(.down(at: Self.pressTime + .milliseconds(280)))
        capture.emit(AudioChunk(samples: samples))
        _ = await read(through: .recording(.handsFree))
        await sut.handle(.up(at: Self.pressTime + .milliseconds(330)))
    }

    /// Lets the timers that the coordinator started so far suspend on the clock, so that an advance cannot come first.
    func waitForTimers(startedAfter before: Int, count: Int) async {
        await clock.waitForSleeps(before + count)
    }
}

@Suite("Dictation coordinator activation", .timeLimit(.minutes(1)))
struct DictationCoordinatorActivationTests {
    private typealias Harness = CoordinatorHarness
    private static let pressTime = DictationCoordinatorTests.pressTime
    private static let transcribed = DictationCoordinatorTests.transcribed

    // MARK: Hold, tap, double tap

    @Test("a hold of 1200 ms starts at the press and finishes at the release")
    func holdStartsAndFinishes() async {
        var h = await Harness()
        await h.startRecording()
        #expect(h.capture.startCount == 1)
        #expect(h.capture.stopCount == 0)

        #expect(await h.release(after: 1_200) == Self.transcribed)
        #expect(h.capture.stopCount == 1)
        #expect(h.inserter.insertedTexts == ["hello"])
    }

    @Test("a tap is discarded, and the double-tap window ends through the clock")
    func tapDiscardsAndTheWindowEnds() async {
        var h = await Harness()
        await h.startRecording()
        let before = h.clock.suspendedSleeps
        #expect(await h.release(after: 80) == [.idle])
        await h.waitForTimers(startedAfter: before, count: 1)

        #expect(h.recognizer.transcribedClips.isEmpty)
        #expect(h.clock.pendingSleeps == 1)  // the window
        h.clock.advance(by: .milliseconds(350))
        for _ in 0..<50 { await Task.yield() }
        #expect(h.clock.pendingSleeps == 0)

        // The window is over, so a second press 200 ms after the release is a new first press, not hands-free.
        await h.sut.handle(.down(at: Self.pressTime + .milliseconds(280)))
        h.capture.emit(AudioChunk(samples: DictationCoordinatorTests.clip))
        #expect(await h.read(through: .recording(.hold)) == [.starting, .recording(.hold)])
    }

    @Test("a double tap records hands-free and keeps recording after the second key comes up")
    func doubleTapKeepsRecording() async {
        var h = await Harness()
        await h.startHandsFree()

        #expect(h.capture.startCount == 2)
        #expect(h.capture.stopCount == 1)  // only the tap's capture has been stopped
        #expect(h.recognizer.transcribedClips.isEmpty)
        #expect(h.inserter.insertedTexts.isEmpty)
    }

    @Test("the next press stops hands-free and submits it, and the key-up that follows is ignored")
    func handsFreeStops() async {
        var h = await Harness()
        await h.startHandsFree()

        await h.sut.handle(.down(at: Self.pressTime + .seconds(5)))
        await h.sut.handle(.up(at: Self.pressTime + .seconds(5) + .milliseconds(90)))

        #expect(await h.read(through: .idle) == Self.transcribed)
        #expect(h.capture.stopCount == 2)
        #expect(h.inserter.insertedTexts == ["hello"])
    }

    @Test("five minutes of silence leave a hands-free recording running")
    func silenceDoesNotStop() async {
        var h = await Harness()
        let before = h.clock.suspendedSleeps
        await h.startHandsFree()
        await h.waitForTimers(startedAfter: before, count: 3)  // the first cap, the window, the second cap

        h.clock.advance(by: .seconds(300))
        for _ in 0..<50 { await Task.yield() }

        #expect(h.capture.stopCount == 1)
        #expect(h.recognizer.transcribedClips.isEmpty)
    }

    // MARK: The 10-minute cap

    @Test("the 10-minute cap finishes a hold with a notice, and the text waits for the key")
    func capFinishesAHold() async {
        var h = await Harness()
        let before = h.clock.suspendedSleeps
        await h.startRecording()
        await h.waitForTimers(startedAfter: before, count: 1)

        h.clock.advance(by: .seconds(600))
        let capped = await h.read(through: .transcribing(progress: nil))
        await h.sleeper.entered(DictationLimits.releaseWaitTimeout).wait()  // the key is still down

        #expect(capped == [.notice(.capReached), .transcribing(progress: nil)])
        #expect(h.inserter.insertedTexts.isEmpty)
        #expect(await h.release(after: 601_000) == [.inserted, .idle])
        #expect(h.diagnostics.events == [.recordingCapReached])
    }

    @Test("the 10-minute cap finishes a hands-free recording with a notice")
    func capFinishesHandsFree() async {
        var h = await Harness()
        let before = h.clock.suspendedSleeps
        await h.startHandsFree()
        await h.waitForTimers(startedAfter: before, count: 3)

        h.clock.advance(by: .seconds(600))

        #expect(
            await h.read(through: .idle)
                == [.notice(.capReached), .transcribing(progress: nil), .inserted, .idle])
        #expect(h.capture.stopCount == 2)
    }

    @Test("a cap that was cancelled by the release never fires")
    func releasedHoldLeavesNoTimer() async {
        var h = await Harness()
        let before = h.clock.suspendedSleeps
        await h.startRecording()
        await h.waitForTimers(startedAfter: before, count: 1)
        _ = await h.release()

        #expect(h.clock.pendingSleeps == 0)
    }

    // MARK: Esc

    @Test(
        "Esc is armed by the press, released by a tap with no job, armed again by hands-free, and released at the end")
    func escapeLifecycle() async {
        var h = await Harness()
        await h.startRecording()
        #expect(h.hotkeys.escapeArmedCalls == [true])

        _ = await h.release(after: 80)  // the tap
        #expect(h.hotkeys.escapeArmedCalls == [true, false])

        await h.sut.handle(.down(at: Self.pressTime + .milliseconds(280)))
        h.capture.emit(AudioChunk(samples: DictationCoordinatorTests.clip))
        _ = await h.read(through: .recording(.handsFree))
        #expect(h.hotkeys.escapeArmedCalls == [true, false, true])

        await h.sut.handle(.down(at: Self.pressTime + .seconds(2)))
        await h.sut.handle(.up(at: Self.pressTime + .seconds(2) + .milliseconds(80)))
        _ = await h.read(through: .idle)
        #expect(h.hotkeys.escapeArmedCalls == [true, false, true, false])
    }

    @Test("Esc stays armed while the dictation is processed and is released when it ends")
    func escapeStaysArmedForTheJob() async {
        var h = await Harness(recognizer: FakeRecognizer(transcript: "uno", gated: true))
        await h.startProcessing()
        #expect(h.hotkeys.escapeArmedCalls == [true])

        h.recognizer.releaseTranscription()
        _ = await h.read(through: .idle)
        #expect(h.hotkeys.escapeArmedCalls == [true, false])
    }

    @Test("Esc while recording cancels the capture, keeps the audio out of the pipeline, and inserts nothing")
    func escapeCancelsRecording() async {
        var h = await Harness()
        await h.startRecording()

        await h.sut.handle(.escape)

        #expect(await h.read(through: .idle) == [.idle])
        #expect(h.capture.stopCount == 1)
        #expect(h.recognizer.transcribedClips.isEmpty)
        #expect(h.inserter.insertedTexts.isEmpty)
        #expect(h.hotkeys.escapeArmedCalls == [true, false])
        #expect(h.clock.pendingSleeps == 0)
    }

    @Test("Esc during hands-free cancels it")
    func escapeCancelsHandsFree() async {
        var h = await Harness()
        await h.startHandsFree()

        await h.sut.handle(.escape)

        #expect(await h.read(through: .idle) == [.idle])
        #expect(h.capture.stopCount == 2)
        #expect(h.inserter.insertedTexts.isEmpty)
    }

    @Test("Esc during transcription ends quietly, and text that returns later is discarded")
    func escapeCancelsTranscription() async {
        var h = await Harness(recognizer: FakeRecognizer(transcript: "uno", gated: true))
        await h.startProcessing()
        await h.recognizer.transcribeEntered.wait()

        await h.sut.handle(.escape)
        #expect(await h.read(through: .idle) == [.idle])  // no error is shown
        h.recognizer.releaseTranscription()
        for _ in 0..<100 { await Task.yield() }

        #expect(h.inserter.insertedTexts.isEmpty)
        #expect(h.hotkeys.escapeArmedCalls == [true, false])
        #expect(h.diagnostics.events.isEmpty)
    }

    @Test("Esc with nothing in flight changes nothing")
    func escapeWhenIdle() async {
        let h = await Harness()

        await h.sut.handle(.escape)

        #expect(h.hotkeys.escapeArmedCalls.isEmpty)
        #expect(h.capture.startCount == 0)
    }

    @Test("a dictation can start after Esc cancelled the one before")
    func dictationAfterEscape() async {
        var h = await Harness()
        await h.startRecording()
        await h.sut.handle(.escape)
        _ = await h.read(through: .idle)

        await h.startRecording(samples: [0.7])

        #expect(await h.release() == Self.transcribed)
        #expect(h.recognizer.transcribedClips == [AudioClip(samples: [0.7])])
    }

    // MARK: Start

    @Test("a failed precondition publishes the error with its remedy and starts no capture or Esc")
    func preconditionFailure() async {
        var h = await Harness(permissions: FakePermissionsChecker([.microphone: .denied]))

        await h.sut.handle(.down(at: Self.pressTime))

        #expect(await h.read(through: .idle) == [.error(.microphoneNotGranted), .idle])
        #expect(PipelineError.microphoneNotGranted.remedy == .permissions)
        #expect(h.capture.startCount == 0)
        #expect(h.hotkeys.escapeArmedCalls.isEmpty)
        #expect(h.clock.pendingSleeps == 0)
    }

    @Test("the state is starting until the first audio arrives, then recording in the mode of the press")
    func startingUntilAudio() async {
        var h = await Harness()
        await h.sut.handle(.down(at: Self.pressTime))
        #expect(await h.read(through: .starting) == [.starting])
        h.capture.emit(AudioChunk(samples: DictationCoordinatorTests.clip))
        #expect(await h.read(through: .recording(.hold)) == [.recording(.hold)])
        _ = await h.release(after: 80)

        await h.sut.handle(.down(at: Self.pressTime + .milliseconds(280)))
        #expect(await h.read(through: .starting) == [.starting])
        h.capture.emit(AudioChunk(samples: DictationCoordinatorTests.clip))
        #expect(await h.read(through: .recording(.handsFree)) == [.recording(.handsFree)])
    }

    @Test("a capture that fails to start in the double-tap window releases Esc and returns to idle")
    func secondStartFails() async {
        let capture = FakeAudioCaptureSource(startFailure: CaptureError.noInputDevice)
        var h = await Harness(capture: capture)

        await h.sut.handle(.down(at: Self.pressTime))

        #expect(
            await h.read(through: .idle) == [
                .starting, .error(.captureFailed(String(describing: CaptureError.noInputDevice))), .idle,
            ])
        #expect(h.hotkeys.escapeArmedCalls == [true, false])
        #expect(h.clock.pendingSleeps == 0)
    }

    // MARK: Levels

    @Test("the input level of the chunks that arrive while recording is published, for the overlay's meter")
    func levelsArePublished() async {
        var h = await Harness()
        var levels = h.sut.levels.makeAsyncIterator()

        await h.startRecording(samples: [Float](repeating: 0.5, count: 160))

        #expect(await levels.next() == 1)
        _ = await h.release()
    }

    // MARK: Timers

    @Test("shutting down cancels every timer")
    func shutdownCancelsTimers() async {
        var h = await Harness()
        let before = h.clock.suspendedSleeps
        await h.startHandsFree()
        await h.waitForTimers(startedAfter: before, count: 3)

        await h.sut.shutdown()

        #expect(h.clock.pendingSleeps == 0)
        #expect(h.hotkeys.escapeArmedCalls.last == false)
    }
}
