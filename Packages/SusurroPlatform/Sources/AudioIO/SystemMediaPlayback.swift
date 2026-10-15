import AppKit
import CoreAudio
import Domain

/// Tells whether another app plays sound and sends the play/pause media key, with public APIs only (ADR 0031).
///
/// "Playing" is read from CoreAudio's process objects: another process whose output is running. The media key goes to
/// the app the system treats as the one that plays media now, the same one the keyboard's play key reaches. The two can
/// differ, for example during a call while the music app is paused, which is why the feature is off by default. It needs
/// sound output and posting events (Accessibility), so it is covered by the manual check; the policy that uses it
/// (`MediaPauser`) is tested.
public struct SystemMediaPlayback: MediaPlaybackControlling {
    /// `NX_KEYTYPE_PLAY` in `IOKit/hidsystem/ev_keymap.h`.
    private static let playKey = 16
    /// `NX_SUBTYPE_AUX_CONTROL_BUTTONS`: the subtype of the media keys' system-defined events.
    private static let auxControlButtons: Int16 = 8

    public init() {}

    public func isPlaying() async -> Bool {
        let me = getpid()
        return Self.processObjects().contains { process in
            Self.pid(of: process) != me && Self.isRunningOutput(process)
        }
    }

    public func togglePlayPause() async {
        await MainActor.run {
            Self.post(down: true)
            Self.post(down: false)
        }
    }

    @MainActor
    private static func post(down: Bool) {
        let state = down ? 0xA : 0xB
        let event = NSEvent.otherEvent(
            with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state) << 8),
            timestamp: 0, windowNumber: 0, context: nil, subtype: auxControlButtons,
            data1: (playKey << 16) | (state << 8), data2: -1)
        event?.cgEvent?.post(tap: .cghidEventTap)
    }

    // MARK: CoreAudio

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func processObjects() -> [AudioObjectID] {
        var address = address(kAudioHardwarePropertyProcessObjectList)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func pid(of process: AudioObjectID) -> pid_t? {
        var address = address(kAudioProcessPropertyPID)
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        return AudioObjectGetPropertyData(process, &address, 0, nil, &size, &pid) == noErr ? pid : nil
    }

    private static func isRunningOutput(_ process: AudioObjectID) -> Bool {
        var address = address(kAudioProcessPropertyIsRunningOutput)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(process, &address, 0, nil, &size, &running) == noErr && running != 0
    }
}
