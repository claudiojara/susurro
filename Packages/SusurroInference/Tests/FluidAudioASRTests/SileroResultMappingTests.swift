import Domain
import Foundation
import Testing

@testable import FluidAudioASR

@Suite("Silero result mapping", .timeLimit(.minutes(1)))
struct SileroResultMappingTests {
    private struct ScriptedEngine: SileroEngine {
        let segments: [SileroSegment]
        var failure: (any Error)?

        func speechSegments(in samples: [Float]) async throws -> [SileroSegment] {
            if let failure { throw failure }
            return segments
        }
    }

    private struct Failure: Error {}

    private static func clip(seconds: Double) -> AudioClip {
        AudioClip(samples: [Float](repeating: 0.1, count: Int(seconds * 16_000)))
    }

    @Test("FluidAudio segments become speech segments in seconds from the start of the clip")
    func mapsSegments() async throws {
        let engine = ScriptedEngine(segments: [
            SileroSegment(start: 2.0, end: 5.0), SileroSegment(start: 7.25, end: 9.5),
        ])
        let result = try await SileroVADDetector(engine: engine).analyze(Self.clip(seconds: 10))

        #expect(
            result
                == VADResult(segments: [
                    SpeechSegment(start: .seconds(2), end: .seconds(5)),
                    SpeechSegment(start: .seconds(7.25), end: .seconds(9.5)),
                ]))
    }

    @Test("segments come out in time order, inside the clip, and without empty or invalid ones")
    func normalizes() async throws {
        let engine = ScriptedEngine(segments: [
            SileroSegment(start: 6, end: 8),
            SileroSegment(start: -1, end: 1),
            SileroSegment(start: 9, end: 12),
            SileroSegment(start: 3, end: 3),
            SileroSegment(start: 5, end: 4),
            SileroSegment(start: .nan, end: 2),
            SileroSegment(start: 1, end: .infinity),
            SileroSegment(start: 11, end: 12),
        ])
        let result = try await SileroVADDetector(engine: engine).analyze(Self.clip(seconds: 10))

        #expect(
            result.segments == [
                SpeechSegment(start: .zero, end: .seconds(1)),
                SpeechSegment(start: .seconds(6), end: .seconds(8)),
                SpeechSegment(start: .seconds(9), end: .seconds(10)),
            ])
    }

    @Test("no segments means no speech, and an empty clip is not analyzed")
    func noSpeech() async throws {
        let detector = SileroVADDetector(engine: ScriptedEngine(segments: [], failure: Failure()))

        #expect(try await detector.analyze(AudioClip(samples: [])).hasSpeech == false)
        await #expect(throws: Failure.self) { try await detector.analyze(Self.clip(seconds: 1)) }
        let quiet = SileroVADDetector(engine: ScriptedEngine(segments: []))
        #expect(try await quiet.analyze(Self.clip(seconds: 1)).hasSpeech == false)
    }

    @Test("the pinned commit is a full revision hash of the Silero repository")
    func pinnedRevision() {
        #expect(LiveSileroEngine.weightsRepository == "FluidInference/silero-vad-coreml")
        #expect(LiveSileroEngine.weightsRevision.count == 40)
        let isHex = LiveSileroEngine.weightsRevision.allSatisfy { $0.isHexDigit }
        #expect(isHex)
    }
}
