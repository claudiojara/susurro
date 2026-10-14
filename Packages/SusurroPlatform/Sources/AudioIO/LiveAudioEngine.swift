import AVFoundation
import Synchronization

/// `AVAudioEngine` behind the `EngineProviding` seam. It needs a microphone and its permission, so it is covered by the
/// manual check in WS5.8 rather than by unit tests.
final class LiveAudioEngine: EngineProviding {
    /// About 21 ms at 48 kHz: the last buffer is dropped when the tap is removed, so a smaller one clips less speech.
    private static let tapBufferSize: AVAudioFrameCount = 1_024

    /// `AVAudioEngine` is not `Sendable`. The lock serializes the calls and keeps this wrapper `Sendable` without an
    /// unchecked escape hatch.
    private let engine = Mutex(AVAudioEngine())

    func inputFormat() -> AVAudioFormat? {
        engine.withLock { engine in
            let format = engine.inputNode.outputFormat(forBus: 0)
            // A machine without an input device reports a format with no sample rate and no channels.
            return format.sampleRate > 0 && format.channelCount > 0 ? format : nil
        }
    }

    func installTap(format: AVAudioFormat, handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        engine.withLock { engine in
            engine.inputNode.installTap(onBus: 0, bufferSize: Self.tapBufferSize, format: format) { buffer, _ in
                handler(buffer)
            }
        }
    }

    func removeTap() {
        engine.withLock { $0.inputNode.removeTap(onBus: 0) }
    }

    func start() throws {
        try engine.withLock { try $0.start() }
    }

    func configurationChanges() -> AsyncStream<Void> {
        // The notification names the engine that posted it, and `stop()` replaces the engine, so only the current one
        // counts.
        let current = engine.withLock { ObjectIdentifier($0) }
        return AsyncStream { continuation in
            let watching = Task {
                for await notification in NotificationCenter.default.notifications(
                    named: .AVAudioEngineConfigurationChange)
                {
                    if let poster = notification.object as AnyObject?, ObjectIdentifier(poster) == current {
                        continuation.yield()
                    }
                }
            }
            continuation.onTermination = { _ in watching.cancel() }
        }
    }

    func stop() {
        // A new engine per capture, so the next one binds to whichever input device is the default by then.
        engine.withLock { engine in
            engine.stop()
            engine = AVAudioEngine()
        }
    }
}
