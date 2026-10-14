import Domain
import Synchronization

/// The hotkey of the app as a `HotkeySource`, configured by the user's settings (`hotkey.kind` and `hotkey.combo`).
///
/// Nothing is registered until `events()` is called. Then the service reads the configuration and listens for it. A
/// keyed hotkey needs no permission. A modifier-only or fn hotkey is not armed until Input Monitoring is granted: the
/// service checks again every `recheckInterval` until it is, and it follows the settings, so a hotkey the user changes is
/// listened to without a relaunch. The registration ends when the stream is no longer read. Presses that happen before
/// the registration has completed are not delivered.
///
/// Esc is another matter: it is registered by `setEscapeArmed(true)` and by nothing else, and its presses arrive on the
/// same stream as `HotkeyEvent.escape`.
public final class HotkeyService: HotkeySource {
    private let settings: any SettingsStore
    private let permissions: any PermissionsChecker
    private let secureInput: any SecureInputProbe
    private let source: any KeyTransitionSource
    private let escape: any EscapeRegistration
    private let now: @Sendable () -> Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let recheckInterval: Duration

    /// Where Esc presses go: the events stream that is being read.
    private let sink = EventSink()
    private let escapeIsArmed = Mutex(false)

    /// The live service, with timestamps measured from creation.
    public convenience init(settings: any SettingsStore, permissions: any PermissionsChecker) {
        let origin = ContinuousClock.now
        self.init(
            settings: settings, permissions: permissions, secureInput: SystemSecureInputProbe(),
            source: KeyboardShortcutsTransitionSource(), escape: KeyboardShortcutsEscapeRegistration(),
            now: { origin.duration(to: .now) }, sleep: { try await Task.sleep(for: $0) }, recheckInterval: .seconds(2))
    }

    init(
        settings: any SettingsStore,
        permissions: any PermissionsChecker,
        secureInput: any SecureInputProbe,
        source: any KeyTransitionSource,
        escape: any EscapeRegistration,
        now: @escaping @Sendable () -> Duration,
        sleep: @escaping @Sendable (Duration) async throws -> Void,
        recheckInterval: Duration
    ) {
        self.settings = settings
        self.permissions = permissions
        self.secureInput = secureInput
        self.source = source
        self.escape = escape
        self.now = now
        self.sleep = sleep
        self.recheckInterval = recheckInterval
    }

    public func events() -> AsyncStream<HotkeyEvent> {
        let (events, continuation) = AsyncStream.makeStream(of: HotkeyEvent.self)
        sink.set(continuation)
        let changes = settings.changes()
        let supervising = Task { await self.supervise(changes: changes, into: continuation) }
        continuation.onTermination = { [sink] _ in
            supervising.cancel()
            sink.clear()
        }
        return events
    }

    /// Whether the hotkey is listening and what the user should know about it. A hotkey that needs Input Monitoring and
    /// does not have it is not armed, and while Secure Event Input is on a warning is exposed.
    public func status() async -> HotkeyStatus {
        await status(of: settings.hotkeyConfiguration())
    }

    public func setEscapeArmed(_ armed: Bool) {
        escapeIsArmed.withLock { current in
            guard current != armed else { return }
            current = armed
            if armed {
                escape.register { [sink] in sink.yield(.escape) }
            } else {
                escape.unregister()
            }
        }
    }

    // MARK: Listening

    private func status(of configuration: HotkeyConfiguration) async -> HotkeyStatus {
        let inputMonitoring: PermissionStatus =
            configuration.needsInputMonitoring ? await permissions.status(.inputMonitoring) : .granted
        return HotkeyStatus.evaluate(
            configuration, inputMonitoring: inputMonitoring, secureInputActive: secureInput.isActive())
    }

    /// Listens for the configured hotkey and follows changes of it, until the stream is no longer read.
    private func supervise(
        changes: AsyncStream<SettingChange>, into continuation: AsyncStream<HotkeyEvent>.Continuation
    ) async {
        let (triggers, trigger) = AsyncStream.makeStream(of: Void.self)
        let forwarding = Task {
            for await change in changes where change.name.hasPrefix("hotkey.") { trigger.yield() }
        }
        trigger.yield()
        var listening: Task<Void, Never>?
        var rechecking: Task<Void, Never>?
        var current: (configuration: HotkeyConfiguration, isArmed: Bool)?
        defer {
            forwarding.cancel()
            listening?.cancel()
            rechecking?.cancel()
            trigger.finish()
        }
        for await _ in triggers {
            let configuration = settings.hotkeyConfiguration()
            let isArmed = await status(of: configuration).arming == .armed
            rechecking?.cancel()
            rechecking = nil
            if !isArmed {
                rechecking = Task { [sleep, recheckInterval] in
                    guard (try? await sleep(recheckInterval)) != nil, !Task.isCancelled else { return }
                    trigger.yield()
                }
            }
            if let current, current.configuration == configuration, current.isArmed == isArmed { continue }
            current = (configuration, isArmed)
            listening?.cancel()
            listening = isArmed ? listen(to: configuration, into: continuation) : nil
        }
    }

    private func listen(
        to configuration: HotkeyConfiguration, into continuation: AsyncStream<HotkeyEvent>.Continuation
    ) -> Task<Void, Never> {
        let transitions = source.transitions(for: configuration)
        return Task { [now] in
            var mapper = HotkeyEventMapper(
                modifierTarget: configuration.kind == .modifierOnly ? configuration.combo.modifiers : nil)
            for await transition in transitions {
                if let event = mapper.map(transition, at: now()) { continuation.yield(event) }
            }
            // A source that ends ends the events. A listener that was replaced by a new configuration does not.
            if !Task.isCancelled { continuation.finish() }
        }
    }
}

/// The events stream that is being read, which Esc presses are sent to. It is set when `events()` is called and cleared
/// when the stream is no longer read.
private final class EventSink: Sendable {
    private let continuation = Mutex<AsyncStream<HotkeyEvent>.Continuation?>(nil)

    func set(_ new: AsyncStream<HotkeyEvent>.Continuation) { continuation.withLock { $0 = new } }
    func clear() { continuation.withLock { $0 = nil } }
    func yield(_ event: HotkeyEvent) { _ = continuation.withLock { $0 }?.yield(event) }
}
