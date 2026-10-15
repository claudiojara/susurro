import Domain
import Synchronization

/// Microphones the test connects and disconnects. Each change is sent to every stream that is read.
public final class FakeAudioInputDevices: AudioInputDeviceListing {
    private let devices: Mutex<[AudioInputDevice]>
    private let broadcaster = VoidBroadcaster()

    public init(_ devices: [AudioInputDevice] = []) {
        self.devices = Mutex(devices)
    }

    public func inputDevices() -> [AudioInputDevice] { devices.withLock { $0 } }

    public func deviceChanges() -> AsyncStream<Void> { broadcaster.stream() }

    /// How many streams are read now, so a test can wait for the listener before it changes the devices.
    public var listenerCount: Int { broadcaster.count }

    /// Replaces the connected devices and tells the streams.
    public func set(_ new: [AudioInputDevice]) {
        devices.withLock { $0 = new }
        broadcaster.send()
    }
}

/// Presses of a shortcut that the test makes.
public final class FakeShortcutPresses: ShortcutPressSource {
    private let broadcaster = VoidBroadcaster()

    public init() {}

    public func presses() -> AsyncStream<Void> { broadcaster.stream() }

    /// How many streams are read now, so a test can wait for the listener before it presses.
    public var listenerCount: Int { broadcaster.count }

    public func press() { broadcaster.send() }
}

/// Sends a value to every stream that is read.
final class VoidBroadcaster: Sendable {
    private struct State {
        var nextID = 0
        var subscribers: [Int: AsyncStream<Void>.Continuation] = [:]
    }

    private let state = Mutex(State())

    var count: Int { state.withLock { $0.subscribers.count } }

    func stream() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let id = state.withLock { state in
                defer { state.nextID += 1 }
                state.subscribers[state.nextID] = continuation
                return state.nextID
            }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { _ = $0.subscribers.removeValue(forKey: id) }
            }
        }
    }

    func send() {
        for subscriber in state.withLock({ Array($0.subscribers.values) }) { subscriber.yield() }
    }
}
