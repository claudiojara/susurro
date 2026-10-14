import Domain
import Synchronization

/// Delivers hotkey events scripted by the test. Events sent before anyone listens are buffered. It records every call to
/// `setEscapeArmed`, in order.
public final class FakeHotkeySource: HotkeySource {
    private let stream: AsyncStream<HotkeyEvent>
    private let continuation: AsyncStream<HotkeyEvent>.Continuation
    private let escapeCalls = Mutex<[Bool]>([])

    public init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    public func events() -> AsyncStream<HotkeyEvent> { stream }
    public func send(_ event: HotkeyEvent) { continuation.yield(event) }
    public func finish() { continuation.finish() }

    public func setEscapeArmed(_ armed: Bool) {
        escapeCalls.withLock { $0.append(armed) }
    }

    /// The values `setEscapeArmed` was called with, in order.
    public var escapeArmedCalls: [Bool] { escapeCalls.withLock { $0 } }
}
