import CoreTestSupport
import Domain
import Pipeline
import Testing

@Suite("Capture start deadline", .timeLimit(.minutes(1)))
struct CaptureStartTimeoutTests {
    private typealias Harness = CoordinatorHarness

    /// A capture whose start waits for a gate, and a sleeper that runs out the start deadline and no other.
    private static func stuckStart() -> (FakeAudioCaptureSource, FakeSleeper) {
        (
            FakeAudioCaptureSource(gatesStart: true),
            FakeSleeper(expiring: [DictationLimits.captureStartTimeout])
        )
    }

    @Test("the start deadline is about five seconds, and apart from the stop deadline")
    func limitIsInRange() {
        #expect(DictationLimits.captureStartTimeout >= .seconds(4))
        #expect(DictationLimits.captureStartTimeout <= .seconds(8))
        // The tests expire one deadline by its length, so two deadlines of one capture must differ.
        #expect(DictationLimits.captureStartTimeout != DictationLimits.captureStopTimeout)
    }

    @Test("a capture that never starts times out, is told to stop, and returns the coordinator to idle")
    func startTimesOut() async {
        let (capture, sleeper) = Self.stuckStart()
        var h = await Harness(capture: capture, sleeper: sleeper)
        await h.sut.handle(.down(at: .zero))

        #expect(await h.read(through: .idle) == [.starting, .error(.timedOut(.capture)), .idle])
        #expect(capture.stopCount == 1)
        #expect(h.recognizer.transcribedClips.isEmpty)
        #expect(h.diagnostics.events == [.dictationFailed(kind: "timedOut.capture")])
    }

    @Test("a release that arrives while the start is stuck is dropped when the start times out")
    func releaseWhileStuck() async {
        let capture = FakeAudioCaptureSource(gatesStart: true)
        var h = await Harness(capture: capture)
        let sut = h.sut
        let press = Task { await sut.handle(.down(at: DictationCoordinatorTests.pressTime)) }
        _ = await h.read(through: .starting)
        await sut.handle(.up(at: DictationCoordinatorTests.pressTime + .milliseconds(1200)))
        h.sleeper.fire(DictationLimits.captureStartTimeout)
        await press.value

        #expect(await h.read(through: .idle) == [.error(.timedOut(.capture)), .idle])
        #expect(h.recognizer.transcribedClips.isEmpty)
        #expect(h.inserter.insertedTexts.isEmpty)
    }

    @Test("a start that finishes in time is untouched by its deadline")
    func startInTimeIsQuiet() async {
        var h = await Harness()
        await h.startRecording()

        #expect(await h.release() == DictationCoordinatorTests.transcribed)
        #expect(h.diagnostics.events.isEmpty)
    }
}
