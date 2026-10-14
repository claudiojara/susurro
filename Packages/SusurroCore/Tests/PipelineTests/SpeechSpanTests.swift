import Domain
import Pipeline
import Testing

@Suite("Speech span", .timeLimit(.minutes(1)))
struct SpeechSpanTests {
    private static func segment(_ start: Double, _ end: Double) -> SpeechSegment {
        SpeechSegment(
            start: .milliseconds(Int((start * 1_000).rounded())), end: .milliseconds(Int((end * 1_000).rounded())))
    }

    private static func clip(seconds: Double) -> AudioClip {
        AudioClip(samples: (0..<Int(seconds * 16_000)).map { Float($0) })
    }

    @Test("speech from 2.0 s to 5.0 s gives a recognizer input from 1.55 s to 5.45 s")
    func preRollAndHangover() {
        let range = SpeechSpan.range(of: VADResult(segments: [Self.segment(2, 5)]), within: .seconds(10))

        #expect(range == .milliseconds(1_550)..<(.milliseconds(5_450)))
    }

    @Test("the span stays inside the recording")
    func clamped() {
        let early = SpeechSpan.range(of: VADResult(segments: [Self.segment(0.1, 0.5)]), within: .seconds(10))
        let late = SpeechSpan.range(of: VADResult(segments: [Self.segment(9.8, 10)]), within: .seconds(10))

        #expect(early == .zero..<(.milliseconds(950)))
        #expect(late == .milliseconds(9_350)..<(.seconds(10)))
    }

    @Test("several segments span from the start of the first to the end of the last")
    func severalSegments() {
        let result = VADResult(segments: [Self.segment(1, 2), Self.segment(4, 5), Self.segment(7, 8)])

        #expect(SpeechSpan.range(of: result, within: .seconds(20)) == .milliseconds(550)..<(.milliseconds(8_450)))
    }

    @Test("no segments give no span")
    func noSegments() {
        #expect(SpeechSpan.range(of: VADResult(segments: []), within: .seconds(10)) == nil)
    }

    @Test("a segment that ends where the recording ends is not pushed past it, and an empty span is no span")
    func degenerate() {
        #expect(SpeechSpan.range(of: VADResult(segments: [Self.segment(5, 5)]), within: .seconds(5)) != nil)
        #expect(SpeechSpan.range(of: VADResult(segments: [Self.segment(7, 8)]), within: .seconds(5)) == nil)
    }

    @Test("the recognizer input is the cropped samples, and the source clip is unchanged")
    func croppedInput() throws {
        let source = Self.clip(seconds: 10)
        let before = source
        let input = try #require(SpeechSpan.input(from: source, result: VADResult(segments: [Self.segment(2, 5)])))

        #expect(input.samples.count == 87_200 - 24_800)
        #expect(input.samples.first == 24_800)
        #expect(input.samples.last == 87_199)
        #expect(source == before)
        #expect(source.samples.count == 160_000)
    }

    @Test("no speech gives no input")
    func noInput() {
        #expect(SpeechSpan.input(from: Self.clip(seconds: 1), result: VADResult(segments: [])) == nil)
    }
}
