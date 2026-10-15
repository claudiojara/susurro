import CoreTestSupport
import Domain
import Pipeline
import Testing

@Suite("Media pauser", .timeLimit(.minutes(1)))
struct MediaPauserTests {
    private let playback = FakeMediaPlayback()
    private let settings = InMemorySettingsStore()
    /// Returns at once from the hold threshold, so a recording that starts is past it as soon as the pauser looks.
    private let sleeper = FakeSleeper()

    private func pauser(sleeper: FakeSleeper? = nil) -> MediaPauser {
        let sleeper = sleeper ?? self.sleeper
        return MediaPauser(
            playback: playback, settings: settings, delay: .milliseconds(300), sleep: { try await sleeper.sleep($0) })
    }

    /// Starts a recording and waits until the pauser has looked at the media.
    private func start(_ pauser: MediaPauser, _ state: PipelineState = .starting) async {
        await pauser.observe(state)
        await pauser.settle()
    }

    private func enable() {
        settings.set(true, for: MediaSettings.pauseWhileDictating)
    }

    @Test("it is off by default: a recording with media playing touches nothing")
    func offByDefault() async {
        playback.playing = true
        let pauser = pauser()

        await start(pauser)
        await pauser.observe(.recording(.hold))
        await pauser.observe(.transcribing(progress: nil))

        #expect(playback.toggles == 0)
        #expect(playback.checks == 0)
    }

    @Test("media that plays is paused as the recording starts, and resumed when it ends")
    func pausesAndResumes() async {
        enable()
        playback.playing = true
        let pauser = pauser()

        await start(pauser)
        #expect(playback.toggles == 1)
        await pauser.observe(.recording(.hold))
        await pauser.observe(.recording(.handsFree))
        #expect(playback.toggles == 1)

        await pauser.observe(.transcribing(progress: nil))
        #expect(playback.toggles == 2)
        await pauser.observe(.inserted)
        await pauser.observe(.idle)
        #expect(playback.toggles == 2)
        #expect(playback.checks == 1)
    }

    @Test("nothing playing means nothing is paused and nothing is resumed")
    func nothingPlaying() async {
        enable()
        let pauser = pauser()

        await start(pauser)
        await pauser.observe(.recording(.hold))
        await pauser.observe(.idle)

        #expect(playback.toggles == 0)
        #expect(playback.checks == 1)
    }

    @Test("a cancelled or failed recording resumes what it paused")
    func cancelAndError() async {
        enable()
        playback.playing = true
        let pauser = pauser()

        await start(pauser)
        await pauser.observe(.idle)
        #expect(playback.toggles == 2)

        await start(pauser, .recording(.hold))
        await pauser.observe(.error(.microphoneNotGranted))
        #expect(playback.toggles == 4)
    }

    @Test("turning the setting off during a recording still resumes what was paused")
    func settingOffMidRecording() async {
        enable()
        playback.playing = true
        let pauser = pauser()

        await start(pauser)
        settings.set(false, for: MediaSettings.pauseWhileDictating)
        await pauser.observe(.idle)

        #expect(playback.toggles == 2)
    }

    @Test("a state that is not a recording, with no recording before it, does nothing")
    func idleAlone() async {
        enable()
        playback.playing = true
        let pauser = pauser()

        await pauser.observe(.idle)
        await pauser.observe(.notice(.noSpeech))

        #expect(playback.toggles == 0)
        #expect(playback.checks == 0)
    }

    @Test("each recording checks again")
    func eachRecording() async {
        enable()
        playback.playing = true
        let pauser = pauser()

        await start(pauser)
        await pauser.observe(.idle)
        playback.playing = false
        await start(pauser)
        await pauser.observe(.idle)

        #expect(playback.checks == 2)
        #expect(playback.toggles == 2)
    }

    @Test("a tap, which ends before the hold threshold, touches no media: no blip, and a double tap pauses nothing")
    func tapTouchesNothing() async {
        enable()
        playback.playing = true
        let sleeper = FakeSleeper(blocksPauses: true)
        let pauser = pauser(sleeper: sleeper)

        await pauser.observe(.starting)
        await sleeper.entered(.milliseconds(300)).wait()
        await pauser.observe(.idle)
        sleeper.fire(.milliseconds(300))
        await pauser.settle()

        #expect(playback.toggles == 0)
        #expect(playback.checks == 0)
    }

    @Test("media is paused only once the press has lasted the hold threshold")
    func pausesAfterTheHoldThreshold() async {
        enable()
        playback.playing = true
        let sleeper = FakeSleeper(blocksPauses: true)
        let pauser = pauser(sleeper: sleeper)

        await pauser.observe(.starting)
        await sleeper.entered(.milliseconds(300)).wait()
        #expect(playback.checks == 0)
        await pauser.observe(.recording(.hold))
        sleeper.fire(.milliseconds(300))
        await pauser.settle()
        #expect(playback.toggles == 1)

        await pauser.observe(.transcribing(progress: nil))
        #expect(playback.toggles == 2)
    }
}
