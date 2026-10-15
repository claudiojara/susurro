import Domain
import Synchronization

/// A reader of the focused element whose answer a test changes while the code runs, and that counts its reads. For a
/// scripted sequence of answers, `FakeFocusedContextReader` is simpler.
public final class MutableFocusedContextReader: FocusedContextReader {
    private struct State {
        var snapshot: FocusedContext?
        var reads = 0
    }

    private let state: Mutex<State>

    public init(_ snapshot: FocusedContext? = nil) {
        state = Mutex(State(snapshot: snapshot))
    }

    /// What the next reads give. Nil reads as nothing readable.
    public func set(_ snapshot: FocusedContext?) {
        state.withLock { $0.snapshot = snapshot }
    }

    public var reads: Int { state.withLock { $0.reads } }

    public func snapshot() async -> FocusedContext? {
        state.withLock { state in
            state.reads += 1
            return state.snapshot
        }
    }
}
