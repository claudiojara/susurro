import CoreTestSupport
import Domain
import Testing

@testable import Pipeline

/// Edge cases of the coordinator found in review: a press during the end of a recording, a hold that the capture start
/// latency makes short, and an Esc that races the start of a job.
@Suite("Coordinator edge cases", .timeLimit(.minutes(1)))
struct CoordinatorEdgeCaseTests {
    private typealias Harness = CoordinatorHarness
    private static let pressTime = DictationCoordinatorTests.pressTime
    private static let afterTheCap = pressTime + .seconds(61)

    // MARK: A press while a recording is finishing

    @Test("a press that lands while a capped recording is finishing waits for it, and then starts the next one")
    func pressWhileTheCapFinishes() async {
        let capture = FakeAudioCaptureSource(onStop: .holdStreamOpen)
        var h = await Harness(capture: capture)
        let sut = h.sut
        await sut.handle(.down(at: Self.pressTime))
        capture.emit(AudioChunk(samples: [Float](repeating: 0.5, count: DictationCoordinatorTests.capSamples)))
        // The cap ended the hold, and the recording is finishing: the capture has stopped and its stream is still open.
        await capture.stopped.wait()

        let press = Task { await sut.handle(.down(at: Self.afterTheCap)) }
        // Give the press the turns it needs to reach the coordinator while the recording is still finishing.
        for _ in 0..<100 { await Task.yield() }
        capture.finish()
        await press.value

        #expect(capture.startCount == 2)
        capture.emit(AudioChunk(samples: DictationCoordinatorTests.clip))
        await sut.shutdown()
        _ = await h.read(through: .idle)
    }

    @Test("a press that lands while a recording ended by a lost device is finishing is not dropped either")
    func pressWhileALostDeviceFinishes() async {
        let capture = FakeAudioCaptureSource(onStop: .hang)
        var h = await Harness(capture: capture)
        let sut = h.sut
        await h.startRecording()
        capture.fail(CaptureError.deviceRemoved)
        for _ in 0..<1_000 where capture.stopCount == 0 { await Task.yield() }  // the recording is finishing

        let press = Task { await sut.handle(.down(at: Self.afterTheCap)) }
        for _ in 0..<100 { await Task.yield() }
        h.sleeper.fire(DictationLimits.captureStopTimeout)  // the capture that never stops is given up on
        await press.value

        #expect(capture.startCount == 2)
        await sut.shutdown()
        _ = await h.read(through: .idle)
    }

    // MARK: A hold that is long by the key and short by the audio

    @Test("a hold the key made long enough is processed even when the audio is shorter, by the capture start latency")
    func holdShortInAudio() async {
        var h = await Harness()
        let clip = DictationCoordinatorTests.audio(0.1, seconds: 0.2)
        await h.startRecording(samples: clip)
        let states = await h.release(after: 400)

        #expect(states == DictationCoordinatorTests.transcribed)
        #expect(h.recognizer.transcribedClips.map(\.samples.count) == [clip.count])
        #expect(h.inserter.insertedTexts == ["hello"])
    }

    @Test("a short clip that the recognizer hears nothing in ends as a visible no-speech notice, never silently")
    func shortClipWithNoSpeech() async {
        var h = await Harness(recognizer: FakeRecognizer(transcript: "  "))
        await h.startRecording(samples: DictationCoordinatorTests.audio(0.1, seconds: 0.2))
        let states = await h.release(after: 400)

        #expect(states == [.transcribing(progress: nil), .notice(.noSpeech), .idle])
        #expect(h.inserter.insertedTexts.isEmpty)
    }

    @Test("a recording that Esc cancels keeps no record when it is shorter than the minimum, as before")
    func shortRecordingCancelled() async {
        var h = await Harness()
        await h.startRecording(samples: DictationCoordinatorTests.audio(0.1, seconds: 0.2))
        await h.sut.cancel()
        _ = await h.read(through: .idle)

        #expect(h.history.allRecords.isEmpty)
        #expect(h.recognizer.transcribedClips.isEmpty)
    }

    // MARK: Esc against the start of a job

    @Test("a job that Esc cancelled before it started does nothing when its turn comes, and Esc stays armed")
    func cancelledJobDoesNotRun() async throws {
        let recognizer = FakeRecognizer(transcripts: ["uno", "dos"], gated: true)
        var h = await Harness(recognizer: recognizer)
        await h.startProcessing()
        await h.sut.handle(.down(at: Self.pressTime + .milliseconds(1300)))
        h.capture.emit(AudioChunk(samples: DictationCoordinatorTests.audio(0.7)))
        _ = await h.read(through: .recording(.hold))
        await h.sut.handle(.up(at: Self.pressTime + .milliseconds(2500)))
        // The second dictation waits behind the first. Esc cancels it before it started.
        await h.sut.cancel()
        let second = try #require(h.recordings.finished.last)
        let late = DictationJob(
            recording: h.recordings.stored(AudioClip(samples: DictationCoordinatorTests.audio(0.7)), as: second))

        // The queue had popped the job as Esc came in, so the job reaches the coordinator after the cancellation.
        let outcome = await h.sut.run(late)

        #expect(outcome == .cancelled)
        #expect(h.diagnostics.events.filter { if case .historyWriteFailed = $0 { true } else { false } }.isEmpty)
        #expect(h.history.allRecords.filter { $0.status == .cancelled }.count == 1)
        #expect(h.hotkeys.escapeArmedCalls.last == true)  // the first dictation is still being processed

        recognizer.releaseTranscription()
        _ = await h.read(through: .idle)
        #expect(h.inserter.insertedTexts == ["uno"])
        #expect(h.hotkeys.escapeArmedCalls.last == false)
    }
}
