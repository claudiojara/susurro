import Domain
import Synchronization

/// A detector with a scripted answer. Unless told otherwise, it finds speech in the whole of every clip it is given. It
/// logs the clips it analyzed.
public final class FakeVoiceActivityDetector: VoiceActivityDetector {
    private let segments: [SpeechSegment]?
    private let failure: (any Error)?
    private let gate: Gate?
    private let clips = Mutex<[AudioClip]>([])
    /// Opened when `analyze` is entered.
    public let entered = Gate()

    /// - Parameters:
    ///   - segments: The speech to report, or nil for one segment that covers the whole clip. Empty means no speech.
    ///   - failure: Makes `analyze` throw.
    ///   - gated: Suspends `analyze` until `release()`.
    public init(segments: [SpeechSegment]? = nil, failure: (any Error)? = nil, gated: Bool = false) {
        self.segments = segments
        self.failure = failure
        gate = gated ? Gate() : nil
    }

    public var analyzedClips: [AudioClip] { clips.withLock { $0 } }

    public func release() { gate?.open() }

    public func analyze(_ clip: AudioClip) async throws -> VADResult {
        clips.withLock { $0.append(clip) }
        entered.open()
        await gate?.wait()
        if let failure { throw failure }
        return VADResult(segments: segments ?? [SpeechSegment(start: .zero, end: clip.duration)])
    }
}
