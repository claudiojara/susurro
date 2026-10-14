import Foundation

/// How loud a stretch of audio is, for a level meter.
public enum AudioLevel {
    /// The loudness (RMS) at the bottom of the meter, in decibels relative to full scale. Anything quieter reads 0.
    public static let floorDecibels = -50.0
    /// The loudness at the top of the meter. Anything louder reads 1. Speech into a microphone sits well below it.
    public static let ceilingDecibels = -10.0

    /// The level of `samples` from 0 to 1, on a decibel scale, so that the meter moves with how loud the voice sounds
    /// and not with its raw amplitude. No audio, and silence, read 0.
    public static func level(of samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        var sumOfSquares = 0.0
        for sample in samples { sumOfSquares += Double(sample) * Double(sample) }
        let rms = (sumOfSquares / Double(samples.count)).squareRoot()
        guard rms.isFinite, rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        let fraction = (decibels - floorDecibels) / (ceilingDecibels - floorDecibels)
        return min(max(fraction, 0), 1)
    }
}
