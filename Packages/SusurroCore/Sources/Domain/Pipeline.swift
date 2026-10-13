public enum RecordingMode: Sendable, Equatable {
    case hold
}

public enum NoticeKind: Sendable, Equatable {
    case noSpeech
    case capReached
    case copiedToClipboard(ClipboardReason)
}

/// Where the user goes to recover from an error.
public enum Remedy: Sendable, Equatable {
    /// Grant a permission in System Settings.
    case permissions
    /// Open the app's settings, for example to install the speech model.
    case settings
    /// Dictate again.
    case retry
}

public enum PipelineError: Error, Sendable, Equatable {
    case microphoneNotGranted
    case recognizerNotInstalled
    /// The speech model failed to load. The text is the reason. `retryable` is false when trying again cannot help.
    case recognizerUnavailable(String, retryable: Bool)
    /// The capture failed. The text is the underlying error.
    case captureFailed(String)
    /// The recognizer failed. The text is the underlying error.
    case recognitionFailed(String)
    /// A step did not finish in time and was abandoned.
    case timedOut(Stage)
    /// The transcript is neither in the target app nor on the clipboard.
    case notInserted(NotInsertedReason)

    public enum Stage: Sendable, Equatable {
        case readiness
        case capture
        case transcription
        case insertion
    }

    public var remedy: Remedy {
        switch self {
        case .microphoneNotGranted: .permissions
        case .recognizerNotInstalled: .settings
        case .recognizerUnavailable(_, let retryable): retryable ? .retry : .settings
        case .captureFailed, .recognitionFailed, .timedOut, .notInserted: .retry
        }
    }
}

/// What the dictation pipeline is doing. Every cycle ends in `idle`.
public enum PipelineState: Sendable, Equatable {
    case idle
    /// Recording was requested and no audio has arrived yet.
    case starting
    case recording(RecordingMode)
    /// `progress` is the speech model's load progress while the clip waits for it.
    case transcribing(progress: Double?)
    case inserted
    case notice(NoticeKind)
    case error(PipelineError)
}

/// Where the coordinator hands the final text.
public protocol TextInserter: Sendable {
    func insert(_ text: String) async -> InsertionOutcome
}
