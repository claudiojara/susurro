import CoreTestSupport
import Domain
import Pipeline
import Testing

@Suite("Dictation coordinator diagnostics", .timeLimit(.minutes(1)))
struct CoordinatorDiagnosticsTests {
    private typealias Harness = CoordinatorHarness

    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    @Test("a dictation that goes well logs nothing")
    func quietWhenAllGoesWell() async {
        var h = await Harness()
        await h.startRecording()
        _ = await h.release()

        #expect(h.diagnostics.events.isEmpty)
    }

    @Test("a failed dictation logs the kind of error and never its text")
    func failureLogsOnlyTheKind() async {
        let secret = "the user said: my password is hunter2"
        var h = await Harness(recognizer: FakeRecognizer(failure: Failure(description: secret)))
        await h.startRecording()
        _ = await h.release()

        #expect(h.diagnostics.events == [.dictationFailed(kind: "recognitionFailed")])
        #expect(!String(describing: h.diagnostics.events).contains("hunter2"))
    }

    @Test("each pipeline error is logged under its own kind")
    func kindsAreDistinct() async {
        var h = await Harness(permissions: FakePermissionsChecker([.microphone: .denied]))
        await h.sut.handle(.down(at: .zero))
        _ = await h.read(through: .idle)

        #expect(h.diagnostics.events == [.dictationFailed(kind: "microphoneNotGranted")])
    }

    @Test("notices and insertions are not failures")
    func noticesAreNotLogged() async {
        var h = await Harness(recognizer: FakeRecognizer(transcript: "  "))
        await h.startRecording()
        _ = await h.release()

        #expect(h.diagnostics.events.isEmpty)
    }

    @Test("a capture stream that fails mid-recording is logged by its type, though the audio is kept")
    func captureStreamFailureIsLogged() async {
        var h = await Harness()
        await h.startRecording(samples: DictationCoordinatorTests.audio(0.1))
        h.capture.fail(CaptureError.noInputDevice)
        let states = await h.release()

        #expect(h.diagnostics.events == [.captureStreamFailed(errorType: "CaptureError")])
        #expect(states == DictationCoordinatorTests.transcribed)
    }

    @Test("a capture that does not stop at shutdown is logged as abandoned")
    func abandonedCaptureIsLogged() async {
        let capture = FakeAudioCaptureSource(onStop: .hang)
        let sleeper = FakeSleeper(expiring: [DictationLimits.captureStopTimeout])
        var h = await Harness(capture: capture, sleeper: sleeper)
        await h.startRecording()
        await h.sut.shutdown()

        #expect(h.diagnostics.events == [.captureStopAbandoned])
    }
}
