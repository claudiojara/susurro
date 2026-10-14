import Foundation

extension AudioClip {
    /// The clip as a WAV file: 16 kHz, mono, 16-bit PCM, which every speech service accepts. Samples outside -1...1 are
    /// clamped.
    public func wavData() -> Data {
        let sampleCount = samples.count
        let dataSize = sampleCount * 2
        var data = Data(capacity: 44 + dataSize)
        func append(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
        func append(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let sampleRate = UInt32(Self.sampleRate)
        append("RIFF")
        append(UInt32(36 + dataSize))
        append("WAVE")
        append("fmt ")
        append(UInt32(16))
        append(UInt16(1))  // PCM
        append(UInt16(1))  // mono
        append(sampleRate)
        append(sampleRate * 2)  // bytes per second
        append(UInt16(2))  // bytes per frame
        append(UInt16(16))  // bits per sample
        append("data")
        append(UInt32(dataSize))
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            append(UInt16(bitPattern: Int16((clamped * Float(Int16.max)).rounded())))
        }
        return data
    }
}
