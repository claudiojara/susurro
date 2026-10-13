import AVFoundation
import Testing

@testable import AudioIO

@Suite("Format converter")
struct FormatConverterTests {
    private static let targetRate = 16_000
    /// Samples skipped at each end when a test looks at the steady middle of a conversion, away from filter edges.
    private static let settle = 200

    private func converter(for buffer: AVAudioPCMBuffer) throws -> FormatConverter {
        try FormatConverter(from: buffer.format)
    }

    /// Everything a capture delivers for these buffers: each conversion, then the tail left in the resampler.
    private func convertAll(_ buffers: [AVAudioPCMBuffer]) throws -> [Float] {
        let sut = try converter(for: try #require(buffers.first))
        var samples: [Float] = []
        for buffer in buffers { samples += try sut.convert(buffer) }
        return samples + (try sut.finish())
    }

    @Test(
        "one second at the device format becomes 16000 mono samples",
        arguments: [
            (sampleRate: 48_000.0, channels: 2 as AVAudioChannelCount),
            (sampleRate: 44_100.0, channels: 1),
            (sampleRate: 24_000.0, channels: 3),
            (sampleRate: 96_000.0, channels: 2),
            (sampleRate: 44_100.0, channels: 2),
            (sampleRate: 16_000.0, channels: 2),
            (sampleRate: 48_000.0, channels: 1),
        ]
    )
    func oneSecondBecomes16kMono(device: (sampleRate: Double, channels: AVAudioChannelCount)) throws {
        let buffer = makeBuffer(
            sampleRate: device.sampleRate,
            channels: device.channels,
            frames: Int(device.sampleRate),
            sample: tone(sampleRate: device.sampleRate)
        )

        let samples = try convertAll([buffer])

        #expect(abs(samples.count - Self.targetRate) <= 1)
    }

    @Test("a burst keeps both edges in place, including the very end of the stream")
    func edgesStayInPlace() throws {
        // 100 ms at 48 kHz in four pieces: silence, then a burst from 10 ms to the end.
        let burstStart = 480
        let buffers = tapBuffers(sampleRate: 48_000, count: 4, frames: 1_200) { _, frame in
            frame >= burstStart ? 0.5 : 0
        }

        let samples = try convertAll(buffers)
        let rise = try #require(samples.firstIndex { $0 > 0.25 })
        let fall = try #require(samples.lastIndex { $0 > 0.25 }) + 1

        #expect(abs(samples.count - 1_600) <= 1)
        #expect(abs(rise - 160) <= 1)
        #expect(abs(fall - 1_600) <= 1)
    }

    @Test("the signal survives conversion: amplitude and pitch are kept")
    func signalSurvives() throws {
        let buffer = makeBuffer(sampleRate: 48_000, channels: 2, frames: 48_000, sample: tone(sampleRate: 48_000))

        let samples = try convertAll([buffer])
        let settled = samples.dropFirst(Self.settle).dropLast(Self.settle)
        let peak = try #require(settled.map { abs($0) }.max())
        let risingCrossings = zip(samples, samples.dropFirst()).filter { $0 < 0 && $1 >= 0 }.count

        #expect(abs(peak - 0.5) < 0.01)
        #expect(abs(risingCrossings - 440) <= 2)
    }

    @Test("buffers converted one after another join as if converted in one piece")
    func streamingKeepsState() throws {
        let rate = 48_000.0
        let whole = makeBuffer(sampleRate: rate, channels: 2, frames: 48_000, sample: tone(sampleRate: rate))
        let expected = try convertAll([whole])
        let streamed = try convertAll(
            tapBuffers(sampleRate: rate, count: 10, frames: 4_800, sample: tone(sampleRate: rate)))

        #expect(abs(streamed.count - Self.targetRate) <= 1)
        #expect(streamed.count == expected.count)
        let difference = try #require(zip(streamed, expected).map { abs($0 - $1) }.max())
        #expect(difference < 0.001)
    }

    @Test(
        "channels are averaged, so a signal on either one is kept",
        arguments: [
            (left: 0.4 as Float, right: 0.2 as Float, mixed: 0.3 as Float),
            (left: 0.0, right: 0.6, mixed: 0.3),
            (left: -0.5, right: 0.5, mixed: 0.0),
        ]
    )
    func channelsAreAveraged(levels: (left: Float, right: Float, mixed: Float)) throws {
        let buffer = makeBuffer(sampleRate: 48_000, channels: 2, frames: 48_000) { channel, _ in
            channel == 0 ? levels.left : levels.right
        }

        let samples = try convertAll([buffer])
        let settled = samples.dropFirst(Self.settle).dropLast(Self.settle)

        #expect(!settled.isEmpty)
        #expect(settled.allSatisfy { abs($0 - levels.mixed) < 0.01 })
    }

    @Test("interleaved input gives the same samples as non-interleaved")
    func interleavedInput() throws {
        let planar = makeBuffer(sampleRate: 48_000, channels: 2, frames: 4_800) { channel, frame in
            tone(sampleRate: 48_000)(channel, frame) * (channel == 0 ? 1 : 0.5)
        }
        let interleaved = makeBuffer(sampleRate: 48_000, channels: 2, frames: 4_800, interleaved: true) {
            channel, frame in tone(sampleRate: 48_000)(channel, frame) * (channel == 0 ? 1 : 0.5)
        }

        let fromPlanar = try convertAll([planar])
        let fromInterleaved = try convertAll([interleaved])

        #expect(fromPlanar.count == 1_600)
        #expect(fromInterleaved == fromPlanar)
    }

    @Test("audio already at 16 kHz mono passes through unchanged")
    func alreadyTargetFormat() throws {
        let buffer = makeBuffer(sampleRate: 16_000, channels: 1, frames: 800) { _, frame in Float(frame) / 800 }

        let samples = try converter(for: buffer).convert(buffer)

        #expect(samples == (0..<800).map { Float($0) / 800 })
    }

    @Test("an empty buffer gives no samples")
    func emptyBuffer() throws {
        let buffer = makeBuffer(sampleRate: 48_000, channels: 2, frames: 480) { _, _ in 0.5 }
        let sut = try converter(for: buffer)
        buffer.frameLength = 0

        #expect(try sut.convert(buffer).isEmpty)
    }

    @Test("a buffer in another format than the converter was made for is rejected")
    func formatChange() throws {
        let original = makeBuffer(sampleRate: 48_000, channels: 2, frames: 480) { _, _ in 0.5 }
        let changed = makeBuffer(sampleRate: 44_100, channels: 1, frames: 441) { _, _ in 0.5 }
        let sut = try converter(for: original)

        #expect(throws: FormatConversionError.formatChanged) { try sut.convert(changed) }
    }

    @Test("a buffer that differs from the converter's format only in channel layout is accepted")
    func layoutMetadataIsIgnored() throws {
        let standard = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let sut = try FormatConverter(from: standard)
        // The fixture labels its channels as discrete, where the standard format labels them left and right.
        let buffer = makeBuffer(sampleRate: 48_000, channels: 2, frames: 4_800) { _, _ in 0.5 }

        #expect(try sut.convert(buffer).count + sut.finish().count == 1_600)
    }

    @Test("input that is not Float32 PCM is unsupported")
    func unsupportedInput() throws {
        let format = try #require(
            AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000, channels: 2, interleaved: true)
        )

        #expect(throws: FormatConversionError.unsupportedFormat) { try FormatConverter(from: format) }
    }
}
