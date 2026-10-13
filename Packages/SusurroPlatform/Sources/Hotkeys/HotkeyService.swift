import Domain

/// The hold-to-talk hotkey as a `HotkeySource`. Nothing is registered until `events()` is consumed, and the
/// registration ends with the consumer.
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
        let (events, continuation) = AsyncStream.makeStream(of: HotkeyEvent.self)
        let listening = Task { @MainActor [source, now] in
            var mapper = HotkeyEventMapper()
            for await transition in source.transitions() {
                if let event = mapper.map(transition, at: now()) {
                    continuation.yield(event)
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in listening.cancel() }
        return events
    }
}
