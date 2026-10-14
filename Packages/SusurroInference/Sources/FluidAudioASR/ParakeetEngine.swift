import Foundation

/// The speech engine behind `ParakeetRecognizer`. The live one wraps FluidAudio; tests substitute a fake, so no unit
/// test downloads a model or runs one.
protocol ParakeetEngine: Sendable {
    /// Clips with fewer samples than this are too short for the engine to transcribe.
    var minimumSampleCount: Int { get }

    /// Downloads the model if it is not on disk, then loads it. `progress` receives fractions in 0...1. The engine
    /// may report them out of order, and more than once for each stage.
    func load(progress: @escaping @Sendable (Double) -> Void) async throws

    /// Transcribes a whole 16 kHz mono clip. A `language` of nil lets the engine detect it. `boost` holds the user's
    /// dictionary terms: the engine rescores its transcript against them, and with none it does no extra work.
    func transcribe(_ samples: [Float], language: String?, boost: [String]) async throws -> String
}

/// Thrown by `ParakeetEngine.load` when the weights have to be downloaded and the disk is nearly full. Freeing space
/// fixes it, so the recognizer keeps offering to try again, and the reason says how much is needed.
struct LowDiskSpace: Error, LocalizedError, Equatable {
    /// The free bytes there were.
    let available: Int64

    var errorDescription: String? {
        let gigabytes = Double(LiveParakeetEngine.requiredFreeSpace) / 1_000_000_000
        return
            "There is not enough free disk space to download the speech model. Free about \(gigabytes) GB and try again."
    }
}

/// Thrown by `ParakeetEngine.load` when trying again cannot help, such as a model that fails to compile. Any other
/// error is taken as one that another try may fix, such as a network that is down.
struct PermanentLoadFailure: Error, Equatable {
    let reason: String
}
