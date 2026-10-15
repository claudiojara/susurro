import AVFoundation

/// The slice of `AVAudioEngine` that the capture source needs, so its logic runs against a fake in tests. Later
/// additions, such as observing device removal, should come with a default implementation so existing fakes keep
/// compiling.
protocol EngineProviding: Sendable {
    /// The input device's format, or nil when there is no input device.
    func inputFormat() -> AVAudioFormat?
    /// Installs the tap that receives the device's buffers in `format`, which is the one `inputFormat()` reported. The
    /// handler runs on an audio thread, and the buffer is valid only during the call.
    func installTap(format: AVAudioFormat, handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void)
    func removeTap()
    func start() throws
    func stop()
    /// A value each time the engine's configuration changes while it runs: the input device was unplugged or replaced,
    /// or the route switched. The engine has stopped delivering buffers by then. Call it before `start()`, and read the
    /// stream until the engine is stopped; each run of the engine has its own stream.
    func configurationChanges() -> AsyncStream<Void>
    /// Makes the CoreAudio device `id` the input of the engine. Call it before `inputFormat()`, since the format is the
    /// device's. Without a call the engine uses the system default input.
    func useInputDevice(_ id: UInt32) throws
}

extension EngineProviding {
    /// An engine that reports no changes.
    func configurationChanges() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    /// An engine that always uses the system default input.
    func useInputDevice(_ id: UInt32) throws {}
}

/// CoreAudio refused to make a device the input of the engine. `status` is its `OSStatus`.
struct InputDeviceError: Error, Equatable {
    let status: Int32
}
