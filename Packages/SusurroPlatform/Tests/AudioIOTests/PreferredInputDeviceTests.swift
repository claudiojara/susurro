import CoreTestSupport
import Domain
import Testing

@testable import AudioIO

@Suite("Preferred input device")
struct PreferredInputDeviceTests {
    private let settings = InMemorySettingsStore()
    private let log = RecordingDiagnostics()
    private let devices = FakeAudioInputDevices([
        AudioInputDevice(uid: "builtin", name: "MacBook Pro Microphone"),
        AudioInputDevice(uid: "yeti", name: "Yeti"),
    ])

    private func preferred(ids: [String: UInt32] = ["builtin": 1, "yeti": 2]) -> PreferredInputDevice {
        PreferredInputDevice(settings: settings, devices: devices, deviceID: { ids[$0] }, diagnostics: log)
    }

    @Test("no choice leaves the system default, and logs nothing")
    func systemDefault() {
        #expect(preferred().resolve() == nil)
        #expect(log.events.isEmpty)
    }

    @Test("a chosen device that is connected resolves to its id")
    func connected() {
        settings.set("yeti", for: MicrophoneSettings.deviceUID)

        #expect(preferred().resolve() == 2)
        #expect(log.events.isEmpty)
    }

    @Test("a chosen device that is gone falls back to the system default, and the fallback is logged")
    func missing() {
        settings.set("usb-headset", for: MicrophoneSettings.deviceUID)

        #expect(preferred().resolve() == nil)
        #expect(log.events == [.microphoneFallback])
    }

    @Test("a device listed but with no id by now falls back too")
    func vanishedBetweenListAndLookup() {
        settings.set("yeti", for: MicrophoneSettings.deviceUID)

        #expect(preferred(ids: [:]).resolve() == nil)
        #expect(log.events == [.microphoneFallback])
    }
}
