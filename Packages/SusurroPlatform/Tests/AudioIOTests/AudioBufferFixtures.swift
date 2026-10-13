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
    // More than two channels need an explicit layout.
    let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | channels)!
    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        interleaved: interleaved,
        channelLayout: layout
    )
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
    buffer.frameLength = AVAudioFrameCount(frames)
    let data = buffer.floatChannelData!
    for channel in 0..<Int(channels) {
        for frame in 0..<frames {
            data[channel][frame * buffer.stride] = sample(channel, frame + start)
        }
    }
    return buffer
}

/// A 440 Hz sine at half scale.
func tone(sampleRate: Double) -> (Int, Int) -> Float {
    { _, frame in 0.5 * sin(Float(frame) * 2 * .pi * 440 / Float(sampleRate)) }
}

/// Consecutive stereo pieces of one signal, as a tap would deliver them.
func tapBuffers(
    sampleRate: Double,
    count: Int,
    frames: Int,
    sample: @escaping (Int, Int) -> Float
) -> [AVAudioPCMBuffer] {
    (0..<count).map {
        makeBuffer(sampleRate: sampleRate, channels: 2, frames: frames, startingAt: $0 * frames, sample: sample)
    }
}
