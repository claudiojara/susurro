import Domain
import Synchronization

/// A rewriter with a scripted reply. It records every request. A `gated` rewriter suspends in `rewrite` until
/// `release()` or until its task is cancelled, after opening `entered`; a cancelled call is counted and throws
/// `CancellationError`, as the live engine does.
public final class FakeSelectionRewriter: SelectionRewriter {
    public enum Reply: Sendable {
        case text(String)
        case failure(EngineFailure)
    }

    /// An error the scripted reply throws.
    public struct EngineFailure: Error, Sendable, Equatable {
        public init() {}
    }

    private struct State {
        var requests: [LocalCommandRequest] = []
        var cancellations = 0
    }

    public let entered = Gate()
    public let locality: Locality
    private let reply: Reply
    private let available: CleanerAvailability
    private let gate: Gate?
    private let state = Mutex(State())

    public init(
        reply: Reply = .text("Rewritten."), availability: CleanerAvailability = .available, gated: Bool = false,
        locality: Locality = .local
    ) {
        self.reply = reply
        self.available = availability
        self.locality = locality
        gate = gated ? Gate() : nil
    }

    public var requests: [LocalCommandRequest] { state.withLock { $0.requests } }
    /// How many calls ended because their task was cancelled.
    public var cancellations: Int { state.withLock { $0.cancellations } }

    public func release() { gate?.open() }

    public func availability() async -> CleanerAvailability { available }

    public func rewrite(_ request: LocalCommandRequest) async throws -> String {
        state.withLock { $0.requests.append(request) }
        entered.open()
        await gate?.wait()
        if Task.isCancelled {
            state.withLock { $0.cancellations += 1 }
            throw CancellationError()
        }
        switch reply {
        case .text(let text): return text
        case .failure(let failure): throw failure
        }
    }
}

/// A reader of the focused element with scripted snapshots, one per call, the last one repeating.
public final class FakeFocusedContextReader: FocusedContextReader {
    private let snapshots: [FocusedContext?]
    private let calls = Mutex(0)
    private let selectionCalls = Mutex(0)

    public init(_ snapshots: [FocusedContext?]) {
        self.snapshots = snapshots.isEmpty ? [nil] : snapshots
    }

    /// A reader whose focused element has `selection` selected, every time it is read.
    public convenience init(selection: String) {
        self.init([FocusedContext(selectedText: selection)])
    }

    /// The full snapshots read.
    public var callCount: Int { calls.withLock { $0 } }
    /// The selection reads (`selectionSnapshot`).
    public var selectionCallCount: Int { selectionCalls.withLock { $0 } }

    public func snapshot() async -> FocusedContext? {
        calls.withLock { $0 += 1 }
        return next()
    }

    public func selectionSnapshot() async -> FocusedContext? {
        selectionCalls.withLock { $0 += 1 }
        return next()
    }

    /// The scripted snapshots are shared by both kinds of read, in the order they are made.
    private let served = Mutex(0)

    private func next() -> FocusedContext? {
        let call = served.withLock { served in
            defer { served += 1 }
            return served
        }
        return snapshots[min(call, snapshots.count - 1)]
    }
}
