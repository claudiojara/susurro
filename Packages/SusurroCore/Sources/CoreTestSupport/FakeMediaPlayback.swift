import Domain
import Synchronization

/// Media playback whose state the test sets. A toggle flips it, as the media key does, and is counted.
public final class FakeMediaPlayback: MediaPlaybackControlling {
    private struct State {
        var playing = false
        var toggles = 0
        var checks = 0
    }

    private let state = Mutex(State())

    public init(playing: Bool = false) {
        state.withLock { $0.playing = playing }
    }

    public var playing: Bool {
        get { state.withLock { $0.playing } }
        set { state.withLock { $0.playing = newValue } }
    }

    /// How many times the media key was sent.
    public var toggles: Int { state.withLock { $0.toggles } }
    /// How many times it was asked whether media plays.
    public var checks: Int { state.withLock { $0.checks } }

    public func isPlaying() async -> Bool {
        state.withLock { state in
            state.checks += 1
            return state.playing
        }
    }

    public func togglePlayPause() async {
        state.withLock { state in
            state.toggles += 1
            state.playing.toggle()
        }
    }
}
