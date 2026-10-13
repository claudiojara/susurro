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
}
