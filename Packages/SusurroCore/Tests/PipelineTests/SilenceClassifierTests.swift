import Domain
import Pipeline
import Testing

@Suite("Silence classifier", .timeLimit(.minutes(1)))
struct SilenceClassifierTests {
    private static let speech = VADResult(segments: [SpeechSegment(start: .seconds(1), end: .seconds(2))])
    private static let none = VADResult(segments: [])

    private static func clip(amplitude: Float, seconds: Double = 3) -> AudioClip {
        AudioClip(samples: [Float](repeating: amplitude, count: Int(seconds * 16_000)))
    }

    @Test("a recording of all zeros is a muted microphone, and its notice says the microphone is silent")
    func mutedMicrophone() {
        let verdict = SilenceClassifier.classify(Self.clip(amplitude: 0), result: Self.none)

        #expect(verdict == .mutedMicrophone)
        #expect(verdict.notice == .silentMicrophone)
    }

    @Test("low noise with no segments is no speech in a quiet room")
    func silentRoom() {
        let verdict = SilenceClassifier.classify(Self.clip(amplitude: 0.002), result: Self.none)

        #expect(verdict == .noSpeech)
        #expect(verdict.notice == .noSpeech)
    }

    @Test("speech segments mean speech, with no notice")
    func speech() {
        let verdict = SilenceClassifier.classify(Self.clip(amplitude: 0.1), result: Self.speech)

        #expect(verdict == .speech)
        #expect(verdict.notice == nil)
    }

    @Test(
        "the RMS threshold is the line between a muted microphone and a quiet room",
        arguments: [
            (SilenceClassifier.silentRMS * 0.5, SpeechVerdict.mutedMicrophone),
            (SilenceClassifier.silentRMS * 0.99, .mutedMicrophone),
            (SilenceClassifier.silentRMS, .noSpeech),
            (SilenceClassifier.silentRMS * 2, .noSpeech),
        ]
    )
    func threshold(amplitude: Float, expected: SpeechVerdict) {
        // A constant signal has an RMS equal to its amplitude.
        #expect(SilenceClassifier.classify(Self.clip(amplitude: amplitude), result: Self.none) == expected)
    }

    @Test("an empty recording is a muted microphone")
    func empty() {
        #expect(SilenceClassifier.classify(AudioClip(samples: []), result: Self.none) == .mutedMicrophone)
    }
}
