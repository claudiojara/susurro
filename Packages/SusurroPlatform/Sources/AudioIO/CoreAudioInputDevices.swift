import CoreAudio
import Domain
import Foundation

/// The input devices CoreAudio knows, and a value each time one is added or removed. It needs real hardware, so it is
/// covered by the manual check rather than by unit tests; the choice it feeds (`PreferredInputDevice`) is tested.
public struct CoreAudioInputDevices: AudioInputDeviceListing {
    public init() {}

    public func inputDevices() -> [AudioInputDevice] {
        Self.deviceIDs().compactMap { id in
            guard Self.hasInput(id), let uid = Self.string(id, kAudioDevicePropertyDeviceUID) else { return nil }
            return AudioInputDevice(uid: uid, name: Self.string(id, kAudioObjectPropertyName) ?? uid)
        }
    }

    /// The CoreAudio id of the input device with `uid`, or nil when it is not connected.
    public func deviceID(forUID uid: String) -> UInt32? {
        Self.deviceIDs().first { Self.hasInput($0) && Self.string($0, kAudioDevicePropertyDeviceUID) == uid }
    }

    public func deviceChanges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            var address = Self.address(kAudioHardwarePropertyDevices)
            let queue = DispatchQueue(label: "susurro.audio-devices")
            let listener: @Sendable (UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void = { _, _ in
                continuation.yield()
            }
            let status = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
            guard status == noErr else {
                continuation.finish()
                return
            }
            continuation.onTermination = { _ in
                var address = Self.address(kAudioHardwarePropertyDevices)
                AudioObjectRemovePropertyListenerBlock(
                    AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
            }
        }
    }

    // MARK: CoreAudio

    private static func address(
        _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = address(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    /// Whether the device has an input stream: a microphone, not only a speaker.
    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}
