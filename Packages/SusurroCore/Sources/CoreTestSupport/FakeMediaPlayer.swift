import Domain
import Synchronization

/// A media player whose state the test sets. A pause makes it paused and a play makes it play, as the real commands do,
/// and every call is counted.
public final class FakeMediaPlayer: MediaPlayerControlling {
    private struct State {
        var state: MediaPlayerState
        var checks = 0
        var pauses = 0
        var plays = 0
    }

    private let state: Mutex<State>

    public init(_ state: MediaPlayerState = .notPlaying) {
        self.state = Mutex(State(state: state))
    }

    /// What the player answers when it is asked for its state.
    public var current: MediaPlayerState {
        get { state.withLock { $0.state } }
        set { state.withLock { $0.state = newValue } }
    }

    /// How many times it was asked for its state.
    public var checks: Int { state.withLock { $0.checks } }
    /// How many times it was told to pause.
    public var pauses: Int { state.withLock { $0.pauses } }
    /// How many times it was told to play.
    public var plays: Int { state.withLock { $0.plays } }

    public func state() async -> MediaPlayerState {
        state.withLock { state in
            state.checks += 1
            return state.state
        }
    }

    public func pause() async {
        state.withLock { state in
            state.pauses += 1
            if state.state == .playing { state.state = .notPlaying }
        }
    }

    public func play() async {
        state.withLock { state in
            state.plays += 1
            if state.state == .notPlaying { state.state = .playing }
        }
    }
}
