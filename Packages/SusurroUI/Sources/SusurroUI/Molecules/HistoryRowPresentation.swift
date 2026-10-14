import DesignSystem

extension HistoryRowStatus {
    /// The tint of the symbol beside the word. The tint, the symbol, and the word together tell the statuses apart without
    /// color alone.
    var tint: Tint {
        switch self {
        case .processing: .pending
        case .succeeded: .success
        case .noSpeech: .neutral
        case .failed: .error
        case .cancelled: .warning
        }
    }

    var symbol: String {
        switch self {
        case .processing: "hourglass"
        case .succeeded: "checkmark.circle.fill"
        case .noSpeech: "waveform.slash"
        case .failed: "xmark.circle.fill"
        case .cancelled: "slash.circle"
        }
    }

    /// The tint of the note under the text: a failure or a cancellation reads as one, anything else is plain.
    var noteTint: Tint {
        switch self {
        case .failed: .error
        case .cancelled: .warning
        case .processing, .succeeded, .noSpeech: .neutral
        }
    }
}
