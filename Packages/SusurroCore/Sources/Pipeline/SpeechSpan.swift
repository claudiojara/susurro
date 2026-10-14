import Domain

/// The part of a recording that the recognizer hears: the speech the detector found, with room on both sides so that the
/// first and last words are not cut. The recording itself is never trimmed.
public enum SpeechSpan {
    /// Audio kept before the first word.
    public static let preRoll = Duration.milliseconds(450)
    /// Audio kept after the last word.
    public static let hangover = Duration.milliseconds(450)

    /// When the span starts and ends, from the first segment to the last, clamped to the recording. Nil when there is no
    /// speech, or when the span is empty.
    public static func range(of result: VADResult, within duration: Duration) -> Range<Duration>? {
        guard let first = result.segments.first?.start, let last = result.segments.last?.end else { return nil }
        let start = max(.zero, first - preRoll)
        let end = min(duration, last + hangover)
        return start < end ? start..<end : nil
    }

    /// A copy of the samples of the span. Nil when there is no span.
    public static func input(from clip: AudioClip, result: VADResult) -> AudioClip? {
        guard let range = range(of: result, within: clip.duration) else { return nil }
        let start = min(clip.samples.count, AudioClip.sampleIndex(at: range.lowerBound))
        let end = min(clip.samples.count, AudioClip.sampleIndex(at: range.upperBound))
        guard start < end else { return nil }
        return AudioClip(samples: Array(clip.samples[start..<end]))
    }
}
