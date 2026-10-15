import AudioIO
import Domain
import Foundation
import Synchronization
import Testing

/// An Apple Event transport whose running apps and answers the test sets, and which records what was sent.
private final class FakeAppleEvents: AppleEventSending {
    struct State {
        var running: [String: Int32] = [:]
        var reply: Result<FourCharCode?, AppleEventFailure> = .success(nil)
        var sent: [(AppleEventRequest, Int32)] = []
    }

    let state = Mutex(State())

    var sent: [AppleEventRequest] { state.withLock { $0.sent.map(\.0) } }

    func processIdentifier(of bundleIdentifier: String) -> Int32? {
        state.withLock { $0.running[bundleIdentifier] }
    }

    func send(_ request: AppleEventRequest, to process: Int32) async throws(AppleEventFailure) -> FourCharCode? {
        let reply = state.withLock { state in
            state.sent.append((request, process))
            return state.reply
        }
        return try reply.get()
    }
}

@Suite("Scripted media player")
struct ScriptedMediaPlayerTests {
    private let events = FakeAppleEvents()

    private func player(_ app: ScriptedMediaPlayer.App = .music) -> ScriptedMediaPlayer {
        ScriptedMediaPlayer(app, events: events)
    }

    private func run(_ bundle: String = "com.apple.Music", reply: Result<FourCharCode?, AppleEventFailure>) {
        events.state.withLock {
            $0.running[bundle] = 42
            $0.reply = reply
        }
    }

    @Test("an app that is not open reads as not running, and nothing is sent to it, so nothing launches it")
    func notRunning() async {
        #expect(await player().state() == .notRunning)
        await player().pause()
        await player().play()

        #expect(events.sent.isEmpty)
    }

    @Test("the player state is read from the app's own property")
    func readsPlayerState() async {
        run(reply: .success(FourCharCode(fourCharacters: "kPSP")))
        #expect(await player().state() == .playing)
        #expect(events.sent == [.getProperty(FourCharCode(fourCharacters: "pPlS"))])

        run(reply: .success(FourCharCode(fourCharacters: "kPSp")))
        #expect(await player().state() == .notPlaying)
        run(reply: .success(FourCharCode(fourCharacters: "kPSS")))
        #expect(await player().state() == .notPlaying)
    }

    @Test("a denied Automation permission, or no answer, reads as unavailable")
    func deniedIsUnavailable() async {
        run(reply: .failure(AppleEventFailure(code: -1743)))
        #expect(await player().state() == .unavailable)

        run(reply: .failure(AppleEventFailure(code: -1712)))
        #expect(await player().state() == .unavailable)

        run(reply: .success(nil))
        #expect(await player().state() == .unavailable)
    }

    @Test("pause and play send the app's own commands, never a toggle")
    func commands() async {
        run(reply: .success(nil))
        await player().pause()
        await player().play()
        #expect(
            events.sent == [
                .command(suite: FourCharCode(fourCharacters: "hook"), id: FourCharCode(fourCharacters: "Paus")),
                .command(suite: FourCharCode(fourCharacters: "hook"), id: FourCharCode(fourCharacters: "Play")),
            ])
    }

    @Test("Spotify is addressed by its own bundle and commands")
    func spotify() async {
        run("com.spotify.client", reply: .success(FourCharCode(fourCharacters: "kPSP")))
        #expect(await player(.spotify).state() == .playing)
        await player(.spotify).pause()

        #expect(
            events.sent.last
                == .command(suite: FourCharCode(fourCharacters: "spfy"), id: FourCharCode(fourCharacters: "Paus")))
        #expect(await player(.music).state() == .notRunning)
    }

    @Test("a four-character code reads as its big-endian value")
    func fourCharCode() {
        #expect(FourCharCode(fourCharacters: "kPSP") == 0x6B50_5350)
    }
}
