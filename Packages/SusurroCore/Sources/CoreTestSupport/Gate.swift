/// A suspension point for fakes. `wait()` suspends until `open()`, or until the waiting task is cancelled. Opens made
/// before the wait are remembered.
public final class Gate: Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    public init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    public func open() { continuation.yield() }

    public func wait() async {
        for await _ in stream { return }
    }
}
