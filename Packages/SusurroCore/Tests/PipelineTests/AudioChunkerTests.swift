import Domain
import Pipeline
import Testing

@Suite("Audio chunker", .timeLimit(.minutes(1)))
struct AudioChunkerTests {
    private static let rate = AudioClip.sampleRate

    /// Speech (a constant tone level) of the given lengths in seconds, with `gap` seconds of digital silence between.
    private static func clip(speech lengths: [Double], gap: Double = 0.6) -> AudioClip {
        var samples: [Float] = []
        for (index, length) in lengths.enumerated() {
            if index > 0 { samples += [Float](repeating: 0, count: Int(gap * Double(rate))) }
            samples += [Float](repeating: 0.3, count: Int(length * Double(rate)))
        }
        return AudioClip(samples: samples)
    }

    /// Whether the samples around `boundary` (20 ms either side) are all digital silence.
    private static func isInSilence(_ clip: AudioClip, at boundary: Int) -> Bool {
        let range = max(0, boundary - 160)..<min(clip.samples.count, boundary + 160)
        return clip.samples[range].allSatisfy { $0 == 0 }
    }

    @Test("a ten-minute clip with pauses gives chunks of at most 60 s, each ending in a pause, in order")
    func tenMinutes() {
        // Utterances of 6 s to 14 s: a pause comes within the last quarter (15 s) of every 60 s window.
        let lengths = (0..<60).map { 6.0 + Double($0 % 5) * 2 }
        let source = Self.clip(speech: lengths)
        let ranges = AudioChunker.ranges(of: source, limit: .seconds(60))

        #expect(source.duration > .seconds(540))
        #expect(ranges.count >= 10)
        for range in ranges { #expect(AudioClip.duration(ofSamples: range.count) <= .seconds(60)) }
        for range in ranges.dropLast() { #expect(Self.isInSilence(source, at: range.upperBound)) }
        // Together they are the clip, in order, with nothing missing and nothing twice.
        #expect(ranges.first?.lowerBound == 0)
        #expect(ranges.last?.upperBound == source.samples.count)
        for (before, after) in zip(ranges, ranges.dropFirst()) { #expect(before.upperBound == after.lowerBound) }
        let rejoined = AudioChunker.chunks(of: source, limit: .seconds(60)).flatMap(\.samples)
        #expect(rejoined == source.samples)
    }

    @Test("a clip within the limit, or with no limit, is one chunk")
    func oneChunk() {
        let source = Self.clip(speech: [20, 20, 18])

        #expect(AudioChunker.ranges(of: source, limit: .seconds(60)).count == 1)
        #expect(AudioChunker.ranges(of: source, limit: nil) == [0..<source.samples.count])
        #expect(AudioChunker.ranges(of: source, limit: source.duration) == [0..<source.samples.count])
    }

    @Test("with no pause in the window, the chunk is cut at the limit")
    func hardSplit() {
        let source = Self.clip(speech: [150])
        let ranges = AudioChunker.ranges(of: source, limit: .seconds(60))

        #expect(
            ranges == [
                0..<(60 * Self.rate), (60 * Self.rate)..<(120 * Self.rate), (120 * Self.rate)..<(150 * Self.rate),
            ])
    }

    @Test("a pause before the search window is not used, and one inside it is cut in the middle")
    func windowAndMiddle() {
        // 100 s of speech with a 1 s pause at 20 s (too early for a 60 s limit) and a 2 s pause from 50 s to 52 s.
        var samples: [Float] = []
        func speak(_ seconds: Double) { samples += [Float](repeating: 0.3, count: Int(seconds * 16_000)) }
        func pause(_ seconds: Double) { samples += [Float](repeating: 0, count: Int(seconds * 16_000)) }
        speak(20)
        pause(1)
        speak(29)
        pause(2)
        speak(48)
        let ranges = AudioChunker.ranges(of: AudioClip(samples: samples), limit: .seconds(60))

        #expect(ranges.count == 2)
        // The middle of the 2 s pause, to the frame.
        #expect(abs(ranges[0].upperBound - 51 * Self.rate) <= 320)
    }

    @Test("a room with a hiss still has pauses")
    func noisyRoom() {
        var samples: [Float] = []
        func noise(_ seconds: Double, level: Float) {
            samples += (0..<Int(seconds * 16_000)).map { index in level * (index.isMultiple(of: 2) ? 1 : -1) }
        }
        noise(55, level: 0.2)  // speech
        noise(2, level: 0.006)  // a pause in a room with a hiss
        noise(55, level: 0.2)
        let ranges = AudioChunker.ranges(of: AudioClip(samples: samples), limit: .seconds(60))

        #expect(ranges.count == 2)
        #expect(abs(ranges[0].upperBound - 56 * Self.rate) <= 320)
    }

    @Test("the pieces are never empty and the limit shorter than a frame cannot loop for good")
    func tinyLimit() {
        let source = Self.clip(speech: [3])
        let ranges = AudioChunker.ranges(of: source, limit: .milliseconds(1))

        #expect(ranges.allSatisfy { !$0.isEmpty })
        #expect(ranges.last?.upperBound == source.samples.count)
    }

    @Test("an empty clip is one empty chunk")
    func emptyClip() {
        #expect(AudioChunker.ranges(of: AudioClip(samples: []), limit: .seconds(60)) == [0..<0])
    }
}
