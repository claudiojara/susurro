import CoreTestSupport
import Domain
import Synchronization

@testable import Hotkeys

/// Raw transitions scripted by the test. Each call to `transitions(for:)` is a subscription of its own, `send` goes to the
/// newest one, and a gate opens when a subscription ends.
final class FakeTransitions: KeyTransitionSource {
    private struct State {
        var configurations: [HotkeyConfiguration] = []
        var continuations: [AsyncStream<KeyTransition>.Continuation] = []
        var watchers: [(total: Int, gate: Gate)] = []
    }

    let stoppedListening = Gate()
    private let state = Mutex(State())

    /// The configuration each subscription asked for, in order.
    var subscriptions: [HotkeyConfiguration] { state.withLock { $0.configurations } }

    func transitions(for configuration: HotkeyConfiguration) -> AsyncStream<KeyTransition> {
        let (stream, continuation) = AsyncStream.makeStream(of: KeyTransition.self)
        let stopped = stoppedListening
        continuation.onTermination = { _ in stopped.open() }
        let ready = state.withLock { state -> [Gate] in
            state.configurations.append(configuration)
            state.continuations.append(continuation)
            let ready = state.watchers.filter { $0.total <= state.configurations.count }
            state.watchers.removeAll { $0.total <= state.configurations.count }
            return ready.map(\.gate)
        }
        for gate in ready { gate.open() }
        return stream
    }

    /// Suspends until `total` subscriptions have been made since the start.
    func waitForSubscriptions(_ total: Int) async {
        let gate = state.withLock { state -> Gate? in
            if state.configurations.count >= total { return nil }
            let gate = Gate()
            state.watchers.append((total, gate))
            return gate
        }
        await gate?.wait()
    }

    func send(_ transition: KeyTransition) {
        state.withLock { $0.continuations.last }?.yield(transition)
    }

    /// Sends to the newest subscription for `configuration`, when the service listens to several hotkeys.
    func send(_ transition: KeyTransition, to configuration: HotkeyConfiguration) {
        state.withLock { state in
            state.configurations.lastIndex(of: configuration).map { state.continuations[$0] }
        }?.yield(transition)
    }

    func finish() {
        state.withLock { $0.continuations.last }?.finish()
    }
}

/// Counts the registrations of Esc, and presses it.
final class FakeEscape: EscapeRegistration {
    private struct State {
        var registrations = 0
        var unregistrations = 0
        var isRegistered = false
        var handler: (@Sendable () -> Void)?
    }

    private let state = Mutex(State())

    var registrations: Int { state.withLock { $0.registrations } }
    var unregistrations: Int { state.withLock { $0.unregistrations } }
    var isRegistered: Bool { state.withLock { $0.isRegistered } }

    func register(_ onEscape: @escaping @Sendable () -> Void) {
        state.withLock { state in
            state.registrations += 1
            state.isRegistered = true
            state.handler = onEscape
        }
    }

    func unregister() {
        state.withLock { state in
            state.unregistrations += 1
            state.isRegistered = false
            state.handler = nil
        }
    }

    /// The user presses Esc. Nothing happens when it is not registered, as the system leaves it to the app in front.
    func press() {
        state.withLock { $0.handler }?()
    }
}

struct FakeSecureInput: SecureInputProbe {
    private let active: Bool

    init(active: Bool = false) {
        self.active = active
    }

    func isActive() -> Bool { active }
}

/// A time that the test sets.
final class TestClock: Sendable {
    private let current = Mutex(Duration.zero)
    func set(_ time: Duration) { current.withLock { $0 = time } }
    func now() -> Duration { current.withLock { $0 } }
}

/// The service on fakes, with a handle on each of them.
struct HotkeyRig {
    let source = FakeTransitions()
    let escape = FakeEscape()
    let clock = TestClock()
    let settings = InMemorySettingsStore()
    let permissions: MutablePermissionsChecker
    let sleeper = FakeSleeper()
    let recheckInterval = Duration.seconds(2)
    let service: HotkeyService

    init(permissions: [Permission: PermissionStatus] = [:], secureInput: Bool = false) {
        let checker = MutablePermissionsChecker(permissions)
        self.permissions = checker
        let clock = clock
        let sleeper = sleeper
        service = HotkeyService(
            settings: settings, permissions: checker, secureInput: FakeSecureInput(active: secureInput),
            source: source, escape: escape, now: { clock.now() }, sleep: { try await sleeper.sleep($0) },
            recheckInterval: .seconds(2))
    }

    /// Suspends until the newest subscription is the one for `configuration`. The settings are two keys, so the service
    /// can listen to a half-changed hotkey on the way.
    func waitForSubscription(to configuration: HotkeyConfiguration) async {
        var total = source.subscriptions.count
        while source.subscriptions.last != configuration {
            total += 1
            await source.waitForSubscriptions(total)
        }
    }

    /// Chooses a modifier-only hotkey, as the settings screen does.
    func chooseModifierOnly(_ modifiers: HotkeyModifiers) {
        settings.set(HotkeyKind.modifierOnly, for: HotkeySettings.kind)
        settings.set(HotkeyCombo(keyCode: nil, modifiers: modifiers), for: HotkeySettings.combo)
    }
}
