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
    /// stream until the capture ends.
    func configurationChanges() -> AsyncStream<Void>
}

extension EngineProviding {
    /// An engine that reports no changes.
    func configurationChanges() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}
