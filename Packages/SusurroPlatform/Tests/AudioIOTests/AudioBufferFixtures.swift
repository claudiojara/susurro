import AVFoundation

/// Builds Float32 buffers for the audio tests. `sample` is called with (channel, frame).
func makeBuffer(
    sampleRate: Double,
    channels: AVAudioChannelCount,
    frames: Int,
    interleaved: Bool = false,
    startingAt start: Int = 0,
    sample: (Int, Int) -> Float
) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: channels,
        interleaved: interleaved
    )!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
    buffer.frameLength = AVAudioFrameCount(frames)
    let data = buffer.floatChannelData!
    for channel in 0..<Int(channels) {
        for frame in 0..<frames {
            data[channel][frame * format.stride] = sample(channel, frame + start)
        }
    }
    return buffer
}

/// A 440 Hz sine at half scale.
func tone(sampleRate: Double) -> (Int, Int) -> Float {
    { _, frame in 0.5 * sin(Float(frame) * 2 * .pi * 440 / Float(sampleRate)) }
}
