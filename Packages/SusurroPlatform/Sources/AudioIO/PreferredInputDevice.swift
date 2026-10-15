import Domain

/// The microphone a recording uses, from the user's choice (`MicrophoneSettings.deviceUID`) and the devices connected
/// now. It is read as each capture starts, so a device plugged in since the last one is found. A chosen device that is
/// not connected falls back to the system default, and the fallback is logged.
public struct PreferredInputDevice: Sendable {
    private let settings: any SettingsStore
    private let devices: any AudioInputDeviceListing
    private let deviceID: @Sendable (String) -> UInt32?
    private let diagnostics: any DiagnosticsLog

    /// - Parameter deviceID: The CoreAudio id of the device with a UID, or nil when none is connected.
    public init(
        settings: any SettingsStore, devices: any AudioInputDeviceListing,
        deviceID: @escaping @Sendable (String) -> UInt32?, diagnostics: any DiagnosticsLog
    ) {
        self.settings = settings
        self.devices = devices
        self.deviceID = deviceID
        self.diagnostics = diagnostics
    }

    /// The CoreAudio id of the device to record from, or nil for the system default.
    public func resolve() -> UInt32? {
        let choice = MicrophoneChoice.resolve(
            preferredUID: settings.value(for: MicrophoneSettings.deviceUID), available: devices.inputDevices())
        switch choice {
        case .systemDefault:
            return nil
        case .missing:
            diagnostics.record(.microphoneFallback)
            return nil
        case .device(let uid):
            // The device may go away between the list and the lookup.
            guard let id = deviceID(uid) else {
                diagnostics.record(.microphoneFallback)
                return nil
            }
            return id
        }
    }
}
