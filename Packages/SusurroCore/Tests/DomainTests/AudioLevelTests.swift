import Domain
import Testing

@Suite("Audio level")
struct AudioLevelTests {
    @Test("no audio and silence read 0")
    func silence() {
        #expect(AudioLevel.level(of: []) == 0)
        #expect(AudioLevel.level(of: [Float](repeating: 0, count: 160)) == 0)
    }

    @Test("a signal at the ceiling reads 1, and a louder one does not read more")
    func ceiling() {
        #expect(AudioLevel.level(of: [Float](repeating: 0.5, count: 160)) == 1)  // about -6 dB
        #expect(AudioLevel.level(of: [Float](repeating: 1, count: 160)) == 1)
    }

    @Test("the scale is in decibels: -30 dB is the middle of the meter, and -50 dB is its floor")
    func decibelScale() {
        let middle = AudioLevel.level(of: [Float](repeating: 0.031_622_776, count: 160))  // -30 dB
        let floor = AudioLevel.level(of: [Float](repeating: 0.003_162_277_7, count: 160))  // -50 dB

        #expect(abs(middle - 0.5) < 0.001)
        #expect(floor < 0.001)
    }

    @Test("a louder voice reads higher")
    func monotonic() {
        let levels = [0.002, 0.01, 0.05, 0.2].map { AudioLevel.level(of: [Float](repeating: Float($0), count: 160)) }

        #expect(levels == levels.sorted())
        #expect(Set(levels).count == levels.count)
    }

    @Test("samples that are not numbers read 0")
    func notANumber() {
        #expect(AudioLevel.level(of: [.nan, 0.1]) == 0)
    }
}
