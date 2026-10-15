import CoreTestSupport
import Domain
import Pipeline
import Testing

@Suite("Media pauser", .timeLimit(.minutes(1)))
struct MediaPauserTests {
    private let music = FakeMediaPlayer()
    private let spotify = FakeMediaPlayer()
    private let settings = InMemorySettingsStore()
    /// Returns at once from the hold threshold, so a recording that starts is past it as soon as the pauser looks.
    private let sleeper = FakeSleeper()

    private func pauser(sleeper: FakeSleeper? = nil) -> MediaPauser {
        let sleeper = sleeper ?? self.sleeper
        return MediaPauser(
            players: [music, spotify], settings: settings, delay: .milliseconds(300),
            sleep: { try await sleeper.sleep($0) })
    }

    /// Starts a recording and waits until the pauser has looked at the players.
    private func start(_ pauser: MediaPauser, _ state: PipelineState = .starting) async {
        await pauser.observe(state)
        await pauser.settle()
    }

    private func enable() {
        settings.set(true, for: MediaSettings.pauseWhileDictating)
    }

    private var commands: Int {
        music.pauses + music.plays + spotify.pauses + spotify.plays
    }

    @Test("it is off by default: a recording with music playing asks and sends nothing")
    func offByDefault() async {
        music.current = .playing
        let pauser = pauser()

        await start(pauser)
        await pauser.observe(.recording(.hold))
        await pauser.observe(.transcribing(progress: nil))

        #expect(commands == 0)
        #expect(music.checks == 0)
    }

    @Test("a player that plays is paused as the recording starts, and played again when it ends")
    func pausesAndResumes() async {
        enable()
        music.current = .playing
        let pauser = pauser()

        await start(pauser)
        #expect(music.pauses == 1)
        #expect(music.current == .notPlaying)
        await pauser.observe(.recording(.hold))
        await pauser.observe(.recording(.handsFree))
        #expect(music.plays == 0)

        await pauser.observe(.transcribing(progress: nil))
        #expect(music.plays == 1)
        #expect(music.current == .playing)
        await pauser.observe(.inserted)
        await pauser.observe(.idle)
        #expect(music.plays == 1)
        #expect(music.checks == 1)
    }

    @Test("a paused player is never started: nothing is sent to it, before or after")
    func pausedPlayerIsLeftAlone() async {
        enable()
        music.current = .notPlaying
        let pauser = pauser()

        await start(pauser)
        await pauser.observe(.recording(.hold))
        await pauser.observe(.idle)

        #expect(music.checks == 1)
        #expect(commands == 0)
        #expect(music.current == .notPlaying)
    }

    @Test("a player that is not open is asked nothing more: no command could launch it")
    func notRunningIsNotLaunched() async {
        enable()
        music.current = .notRunning
        spotify.current = .notRunning
        let pauser = pauser()

        await start(pauser)
        await pauser.observe(.idle)

        #expect(commands == 0)
    }

    @Test("a player that cannot be asked, for a denied permission, is skipped and the others still pause")
    func deniedIsSkipped() async {
        enable()
        music.current = .unavailable
        spotify.current = .playing
        let pauser = pauser()

        await start(pauser)
        #expect(music.pauses == 0)
        #expect(spotify.pauses == 1)

        await pauser.observe(.idle)
        #expect(music.plays == 0)
        #expect(spotify.plays == 1)
    }

    @Test("only the players it paused are played again")
    func resumesOnlyWhatItPaused() async {
        enable()
        music.current = .notPlaying
        spotify.current = .playing
        let pauser = pauser()

        await start(pauser)
        await pauser.observe(.idle)

        #expect(music.pauses == 0)
        #expect(music.plays == 0)
        #expect(music.current == .notPlaying)
        #expect(spotify.pauses == 1)
        #expect(spotify.plays == 1)
    }

    @Test("a cancelled or failed recording plays again what it paused")
    func cancelAndError() async {
        enable()
        music.current = .playing
        let pauser = pauser()

        await start(pauser)
        await pauser.observe(.idle)
        #expect(music.plays == 1)

        await start(pauser, .recording(.hold))
        await pauser.observe(.error(.microphoneNotGranted))
        #expect(music.pauses == 2)
        #expect(music.plays == 2)
    }

    @Test("turning the setting off during a recording still plays again what was paused")
    func settingOffMidRecording() async {
        enable()
        music.current = .playing
        let pauser = pauser()

        await start(pauser)
        settings.set(false, for: MediaSettings.pauseWhileDictating)
        await pauser.observe(.idle)

        #expect(music.plays == 1)
    }

    @Test("a state that is not a recording, with no recording before it, does nothing")
    func idleAlone() async {
        enable()
        music.current = .playing
        let pauser = pauser()

        await pauser.observe(.idle)
        await pauser.observe(.notice(.noSpeech))

        #expect(commands == 0)
        #expect(music.checks == 0)
    }

    @Test("each recording asks again, and forgets what the last one paused")
    func eachRecording() async {
        enable()
        music.current = .playing
        let pauser = pauser()

        await start(pauser)
        await pauser.observe(.idle)
        music.current = .notPlaying
        await start(pauser)
        await pauser.observe(.idle)

        #expect(music.checks == 2)
        #expect(music.pauses == 1)
        #expect(music.plays == 1)
    }

    @Test("a tap, which ends before the hold threshold, touches no player: no blip, and a double tap pauses nothing")
    func tapTouchesNothing() async {
        enable()
        music.current = .playing
        let sleeper = FakeSleeper(blocksPauses: true)
        let pauser = pauser(sleeper: sleeper)

        await pauser.observe(.starting)
        await sleeper.entered(.milliseconds(300)).wait()
        await pauser.observe(.idle)
        sleeper.fire(.milliseconds(300))
        await pauser.settle()

        #expect(commands == 0)
        #expect(music.checks == 0)
    }

    @Test("a player is paused only once the press has lasted the hold threshold")
    func pausesAfterTheHoldThreshold() async {
        enable()
        music.current = .playing
        let sleeper = FakeSleeper(blocksPauses: true)
        let pauser = pauser(sleeper: sleeper)

        await pauser.observe(.starting)
        await sleeper.entered(.milliseconds(300)).wait()
        #expect(music.checks == 0)
        await pauser.observe(.recording(.hold))
        sleeper.fire(.milliseconds(300))
        await pauser.settle()
        #expect(music.pauses == 1)

        await pauser.observe(.transcribing(progress: nil))
        #expect(music.plays == 1)
    }
}
