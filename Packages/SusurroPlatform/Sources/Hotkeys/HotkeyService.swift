import Domain

/// The hold-to-talk hotkey as a `HotkeySource`. Nothing is registered until `events()` is called, and then it is
/// registered whether or not the stream is read yet; the registration ends when the stream is no longer read. Presses
/// that happen before the main actor has completed the registration are not delivered.
public final class HotkeyService: HotkeySource {
    private let source: any KeyTransitionSource
    private let now: @Sendable () -> Duration

    /// The live service: Control+Option+D, with timestamps measured from creation.
    public convenience init() {
        let origin = ContinuousClock.now
        self.init(source: KeyboardShortcutsTransitionSource(), now: { origin.duration(to: .now) })
    }

    init(source: any KeyTransitionSource, now: @escaping @Sendable () -> Duration) {
        self.source = source
        self.now = now
    }

    public func events() -> AsyncStream<HotkeyEvent> {
        let transitions = source.transitions()
        let (events, continuation) = AsyncStream.makeStream(of: HotkeyEvent.self)
        let mapping = Task { [now] in
            var mapper = HotkeyEventMapper()
            for await transition in transitions {
                if let event = mapper.map(transition, at: now()) {
                    continuation.yield(event)
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in mapping.cancel() }
        return events
    }
}
