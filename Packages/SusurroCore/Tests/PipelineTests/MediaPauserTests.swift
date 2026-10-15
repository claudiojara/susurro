import CoreTestSupport
import Domain
import Pipeline
import Testing

@Suite("Media pauser", .timeLimit(.minutes(1)))
struct MediaPauserTests {
    private let playback = FakeMediaPlayback()
    private let settings = InMemorySettingsStore()

    private func pauser() -> MediaPauser {
        MediaPauser(playback: playback, settings: settings)
    }

    private func enable() {
        settings.set(true, for: MediaSettings.pauseWhileDictating)
    }

    @Test("it is off by default: a recording with media playing touches nothing")
    func offByDefault() async {
        playback.playing = true
        let pauser = pauser()

        await pauser.observe(.starting)
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

        await pauser.observe(.starting)
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

        await pauser.observe(.starting)
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

        await pauser.observe(.starting)
        await pauser.observe(.idle)
        #expect(playback.toggles == 2)

        await pauser.observe(.recording(.hold))
        await pauser.observe(.error(.microphoneNotGranted))
        #expect(playback.toggles == 4)
    }

    @Test("turning the setting off during a recording still resumes what was paused")
    func settingOffMidRecording() async {
        enable()
        playback.playing = true
        let pauser = pauser()

        await pauser.observe(.starting)
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

        await pauser.observe(.starting)
        await pauser.observe(.idle)
        playback.playing = false
        await pauser.observe(.starting)
        await pauser.observe(.idle)

        #expect(playback.checks == 2)
        #expect(playback.toggles == 2)
    }
}
