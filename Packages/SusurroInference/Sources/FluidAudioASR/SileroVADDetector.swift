import Domain
import Foundation

/// The speech finder behind `SileroVADDetector`. The live one wraps FluidAudio's Silero model; tests substitute a fake, so
/// no unit test downloads a model or runs one.
protocol SileroEngine: Sendable {
    /// The stretches of speech in a 16 kHz mono clip, in seconds from its start. They may come in any order.
    func speechSegments(in samples: [Float]) async throws -> [SileroSegment]
}

struct SileroSegment: Sendable, Equatable {
    let start: TimeInterval
    let end: TimeInterval
}

/// Finds the speech in a recording with the Silero voice activity model, which runs on this Mac. The model downloads on
/// the first recording it analyzes, and it is small. Analysis fails when the model cannot load, so the caller decides what
/// to do without it.
public actor SileroVADDetector: VoiceActivityDetector {
    private let engine: any SileroEngine

    public init() {
        self.init(engine: LiveSileroEngine())
    }

    init(engine: any SileroEngine) {
        self.engine = engine
    }

    public func analyze(_ clip: AudioClip) async throws -> VADResult {
        guard !clip.samples.isEmpty else { return VADResult(segments: []) }
        let found = try await engine.speechSegments(in: clip.samples)
        return VADResult(segments: Self.segments(from: found, within: clip.duration))
    }

    /// The segments in time order and inside the clip. A stretch that is empty, backwards, or not a number is left out.
    static func segments(from found: [SileroSegment], within duration: Duration) -> [SpeechSegment] {
        found
            .filter { $0.start.isFinite && $0.end.isFinite }
            .sorted { $0.start < $1.start }
            .compactMap { segment in
                let start = max(.zero, Duration.seconds(segment.start))
                let end = min(duration, Duration.seconds(segment.end))
                return start < end ? SpeechSegment(start: start, end: end) : nil
            }
    }
}
