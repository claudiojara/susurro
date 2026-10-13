import AVFoundation

enum FormatConversionError: Error, Equatable {
    /// The input is not Float32 PCM, or no converter exists for it.
    case unsupportedFormat
    /// A buffer arrived in another format than the one the converter was made for.
    case formatChanged
    case conversionFailed(String)
}

/// Converts captured buffers to 16 kHz mono Float32, the format every recognizer takes.
///
/// The resampler keeps its filter state between calls, so consecutive buffers of one capture join without gaps or
/// clicks. Make one converter per capture and call it from one thread at a time.
final class FormatConverter {
    static let targetSampleRate = 16_000.0
    /// Room for what the resampler holds back, which is a few dozen samples at most.
    private static let tailCapacity: AVAudioFrameCount = 1_024

    private let inputFormat: AVAudioFormat
    private let monoFormat: AVAudioFormat
    /// Nil when the input is already at the target rate.
    private let resampler: AVAudioConverter?

    init(from inputFormat: AVAudioFormat) throws {
        guard
            inputFormat.commonFormat == .pcmFormatFloat32,
            inputFormat.channelCount > 0,
            let mono = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: inputFormat.sampleRate,
                channels: 1,
                interleaved: false
            ),
            let target = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Self.targetSampleRate,
                channels: 1,
                interleaved: false
            )
        else { throw FormatConversionError.unsupportedFormat }

        self.inputFormat = inputFormat
        monoFormat = inputFormat.channelCount == 1 ? inputFormat : mono
        if inputFormat.sampleRate == Self.targetSampleRate {
            resampler = nil
        } else {
            guard let converter = AVAudioConverter(from: monoFormat, to: target) else {
                throw FormatConversionError.unsupportedFormat
            }
            // Normal priming offsets the filter delay without dropping input, so edges land where they were captured.
            // The default (`.pre`) discards the first ~60 ms of audio, and `.none` delays the whole signal.
            converter.primeMethod = .normal
            resampler = converter
        }
    }

    /// Returns the buffer as 16 kHz mono samples. Channels are averaged, so a signal on any one of them is kept.
    func convert(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        guard matchesInput(buffer.format) else { throw FormatConversionError.formatChanged }
        guard buffer.frameLength > 0 else { return [] }
        let mono = try mixedToMono(buffer)
        guard let resampler else { return samples(of: mono) }
        return try resample(mono, with: resampler)
    }

    /// Returns the last samples, which the resampler holds back until the stream ends. Call it once, after the final
    /// buffer, and not again on the same converter. With it, a capture delivers exactly the expected sample count.
    func finish() throws -> [Float] {
        guard let resampler else { return [] }
        guard let output = AVAudioPCMBuffer(pcmFormat: resampler.outputFormat, frameCapacity: Self.tailCapacity) else {
            throw FormatConversionError.conversionFailed("could not allocate the output buffer")
        }
        var failure: NSError?
        let status = resampler.convert(to: output, error: &failure) { _, inputStatus in
            inputStatus.pointee = .endOfStream
            return nil
        }
        if status == .error {
            throw FormatConversionError.conversionFailed(failure?.localizedDescription ?? "unknown error")
        }
        return samples(of: output)
    }

    /// Compares what conversion depends on. Two formats can differ only in channel layout metadata and still match.
    private func matchesInput(_ format: AVAudioFormat) -> Bool {
        format.sampleRate == inputFormat.sampleRate
            && format.channelCount == inputFormat.channelCount
            && format.commonFormat == inputFormat.commonFormat
            && format.isInterleaved == inputFormat.isInterleaved
    }

    /// Averages the channels into one. This is written by hand because `AVAudioConverter`'s own stereo-to-mono keeps
    /// only the left channel, so a signal on any other channel would vanish.
    private func mixedToMono(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let channels = Int(buffer.format.channelCount)
        guard channels > 1 else { return buffer }
        guard let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: buffer.frameLength),
            let source = buffer.floatChannelData, let destination = mono.floatChannelData?[0]
        else { throw FormatConversionError.conversionFailed("could not allocate the mono buffer") }
        mono.frameLength = buffer.frameLength
        // Interleaved audio keeps every channel in one array, so frame `n` of any channel sits at `n * stride`, where the
        // stride is the channel count. Planar audio has one array per channel and a stride of 1.
        let stride = buffer.stride
        let weight = 1 / Float(channels)
        for frame in 0..<Int(buffer.frameLength) {
            var sum: Float = 0
            for channel in 0..<channels { sum += source[channel][frame * stride] }
            destination[frame] = sum * weight
        }
        return mono
    }

    private func resample(_ input: AVAudioPCMBuffer, with resampler: AVAudioConverter) throws -> [Float] {
        // Sized to the expected output. A larger buffer makes the converter hold audio back until the next call.
        let expected = (Double(input.frameLength) * Self.targetSampleRate / input.format.sampleRate).rounded(.up)
        let capacity = AVAudioFrameCount(expected)
        guard let output = AVAudioPCMBuffer(pcmFormat: resampler.outputFormat, frameCapacity: capacity) else {
            throw FormatConversionError.conversionFailed("could not allocate the output buffer")
        }

        var supplied = false
        var failure: NSError?
        let status = resampler.convert(to: output, error: &failure) { _, inputStatus in
            // The converter asks again when it wants more than this buffer holds. `.noDataNow` ends the call and keeps
            // the filter state for the next buffer, where `.endOfStream` would flush it and end the stream.
            guard !supplied else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        if status == .error {
            throw FormatConversionError.conversionFailed(failure?.localizedDescription ?? "unknown error")
        }
        return samples(of: output)
    }

    private func samples(of buffer: AVAudioPCMBuffer) -> [Float] {
        guard let data = buffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
    }
}
