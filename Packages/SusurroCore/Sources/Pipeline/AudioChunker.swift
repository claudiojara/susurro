import Domain

/// Splits a long clip into pieces a recognizer can take, at pauses in the speech, so no word is cut in two.
///
/// Each piece ends in the middle of the last pause found in the final quarter of the limit, and is never shorter than
/// half the limit. A pause is a run of frames quieter than a threshold taken from the clip itself: three times its noise
/// floor, kept between a floor and a ceiling. Where the window holds no pause, the piece is cut at the limit.
public enum AudioChunker {
    /// The length of the frames whose loudness is compared.
    static let frameSamples = AudioClip.sampleRate / 50  // 20 ms
    /// Frames quieter than this are silence however quiet the clip is: digital silence and the hiss of a quiet room.
    static let silenceFloor: Float = 0.002
    /// Frames louder than this are never silence, however loud the room is.
    static let silenceCeiling: Float = 0.02

    /// The sample ranges of the pieces, in order, with no gap and no overlap. One piece for a clip within the limit or
    /// with no limit.
    public static func ranges(of clip: AudioClip, limit: Duration?) -> [Range<Int>] {
        let count = clip.samples.count
        guard let limit else { return [0..<count] }
        let limitSamples = max(AudioClip.sampleIndex(at: limit), frameSamples * 2)
        guard count > limitSamples else { return [0..<count] }

        let loudness = Self.loudness(of: clip.samples)
        let threshold = Self.threshold(for: loudness)
        let searchBack = limitSamples / 4
        var ranges: [Range<Int>] = []
        var start = 0
        while count - start > limitSamples {
            let windowEnd = start + limitSamples
            let windowStart = max(start + limitSamples / 2, windowEnd - searchBack)
            let cut = Self.pause(in: windowStart..<windowEnd, loudness: loudness, threshold: threshold) ?? windowEnd
            ranges.append(start..<cut)
            start = cut
        }
        ranges.append(start..<count)
        return ranges
    }

    /// The pieces themselves.
    public static func chunks(of clip: AudioClip, limit: Duration?) -> [AudioClip] {
        ranges(of: clip, limit: limit).map { AudioClip(samples: Array(clip.samples[$0])) }
    }

    /// The RMS amplitude of each frame, the last one possibly short.
    private static func loudness(of samples: [Float]) -> [Float] {
        stride(from: 0, to: samples.count, by: frameSamples).map { start in
            let end = min(samples.count, start + frameSamples)
            var sum: Float = 0
            for index in start..<end { sum += samples[index] * samples[index] }
            return (sum / Float(end - start)).squareRoot()
        }
    }

    private static func threshold(for loudness: [Float]) -> Float {
        guard !loudness.isEmpty else { return silenceFloor }
        let floorOfTheClip = loudness.sorted()[loudness.count / 10]
        return min(silenceCeiling, max(silenceFloor, floorOfTheClip * 3))
    }

    /// The middle of the last run of quiet frames that lies inside `window`, as a sample index. Nil when there is none.
    private static func pause(in window: Range<Int>, loudness: [Float], threshold: Float) -> Int? {
        let first = (window.lowerBound + frameSamples - 1) / frameSamples
        let last = window.upperBound / frameSamples  // exclusive: a frame must end inside the window
        guard first < last else { return nil }
        var frame = last - 1
        while frame >= first, loudness[frame] >= threshold { frame -= 1 }
        guard frame >= first else { return nil }
        let runEnd = frame
        while frame > first, loudness[frame - 1] < threshold { frame -= 1 }
        let middle = (frame + runEnd + 1) * frameSamples / 2
        return min(max(middle, window.lowerBound + 1), window.upperBound)
    }
}
