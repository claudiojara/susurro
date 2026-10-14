import Domain

/// What a recording turned out to hold.
public enum SpeechVerdict: Sendable, Equatable {
    /// Someone spoke.
    case speech
    /// Nobody spoke: a quiet room, or noise.
    case noSpeech
    /// The signal is digital silence, so the microphone is muted, disconnected, or blocked.
    case mutedMicrophone

    /// What to tell the user, or nil when there is something to transcribe.
    public var notice: NoticeKind? {
        switch self {
        case .speech: nil
        case .noSpeech: .noSpeech
        case .mutedMicrophone: .silentMicrophone
        }
    }
}

/// Tells a muted microphone from a quiet room, from the signal and from what the detector found.
public enum SilenceClassifier {
    /// The RMS amplitude (full scale is 1) below which a recording counts as digital silence: about -80 dBFS. A muted
    /// microphone delivers exact zeros. A real room, even a very quiet one, sits an order of magnitude above this.
    public static let silentRMS: Float = 0.0001

    public static func classify(_ clip: AudioClip, result: VADResult) -> SpeechVerdict {
        if rms(of: clip.samples) < silentRMS { return .mutedMicrophone }
        return result.hasSpeech ? .speech : .noSpeech
    }

    static func rms(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        return (sum / Float(samples.count)).squareRoot()
    }
}
