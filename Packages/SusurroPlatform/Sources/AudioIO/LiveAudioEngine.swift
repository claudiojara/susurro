import AVFoundation
import Synchronization

/// `AVAudioEngine` behind the `EngineProviding` seam. It needs a microphone and its permission, so it is covered by the
/// manual check in WS5 rather than by unit tests.
final class LiveAudioEngine: EngineProviding {
    private static let tapBufferSize: AVAudioFrameCount = 4_096

    private let engine = Mutex(AVAudioEngine())

    func inputFormat() -> AVAudioFormat? {
        engine.withLock { engine in
            let format = engine.inputNode.outputFormat(forBus: 0)
            // A machine without an input device reports a format with no sample rate and no channels.
            return format.sampleRate > 0 && format.channelCount > 0 ? format : nil
        }
    }

    func installTap(handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        engine.withLock { engine in
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: Self.tapBufferSize, format: input.outputFormat(forBus: 0)) {
                buffer, _ in handler(buffer)
            }
        }
    }

    func removeTap() {
        engine.withLock { $0.inputNode.removeTap(onBus: 0) }
    }

    func start() throws {
        try engine.withLock { try $0.start() }
    }

    func stop() {
        // A new engine per capture, so the next one binds to whichever input device is the default by then.
        engine.withLock { engine in
            engine.stop()
            engine = AVAudioEngine()
        }
    }
}
