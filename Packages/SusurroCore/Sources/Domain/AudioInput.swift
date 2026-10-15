/// A microphone the user can pick: a CoreAudio input device, named by its UID, which stays the same across launches and
/// reconnections, unlike its numeric id.
public struct AudioInputDevice: Sendable, Equatable, Identifiable {
    public let uid: String
    public let name: String

    public var id: String { uid }

    public init(uid: String, name: String) {
        self.uid = uid
        self.name = name
    }
}

/// The microphones that are connected now, and a value each time one connects or goes away. The live one asks
/// CoreAudio; tests script their own.
public protocol AudioInputDeviceListing: Sendable {
    func inputDevices() -> [AudioInputDevice]
    /// A new stream on each call: a value each time the list of devices changes, until the stream is no longer read.
    func deviceChanges() -> AsyncStream<Void>
}

/// A machine with no microphones to list, for graphs that do not offer the choice.
public struct NoAudioInputDevices: AudioInputDeviceListing {
    public init() {}

    public func inputDevices() -> [AudioInputDevice] { [] }

    public func deviceChanges() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

/// The microphone the user chose, stored as `microphone.deviceUID`. Empty means the system default, which is what the app
/// used before the choice existed.
public enum MicrophoneSettings {
    public static let deviceUID = SettingKey<String>(area: "microphone", name: "deviceUID", default: "")

    public static let all: [any AnySettingKey] = [deviceUID]
}

/// Which microphone a recording uses. A pure rule, so the capture and the settings agree on it.
public enum MicrophoneChoice: Sendable, Equatable {
    case systemDefault
    /// The chosen device, which is connected.
    case device(uid: String)
    /// The chosen device is not connected, so the recording uses the system default.
    case missing(uid: String)

    public static func resolve(preferredUID: String, available: [AudioInputDevice]) -> MicrophoneChoice {
        guard !preferredUID.isEmpty else { return .systemDefault }
        return available.contains { $0.uid == preferredUID } ? .device(uid: preferredUID) : .missing(uid: preferredUID)
    }
}
