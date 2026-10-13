import Domain

/// Delivers hotkey events scripted by the test. Events sent before anyone listens are buffered.
public final class FakeHotkeySource: HotkeySource {
    private let stream: AsyncStream<HotkeyEvent>
    private let continuation: AsyncStream<HotkeyEvent>.Continuation

    public init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    public func events() -> AsyncStream<HotkeyEvent> { stream }

    public func send(_ event: HotkeyEvent) { continuation.yield(event) }

    public func finish() { continuation.finish() }

    public func setEscapeArmed(_ armed: Bool) {}
}
