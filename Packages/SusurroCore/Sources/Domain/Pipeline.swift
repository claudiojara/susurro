public enum RecordingMode: Sendable, Equatable {
    case hold
}

public enum NoticeKind: Sendable, Equatable {
    case noSpeech
    case capReached
    case copiedToClipboard(ClipboardReason)
    /// A press arrived while the last dictation was still being transcribed or inserted, so it was ignored. The
    /// pipeline state that was showing comes right back after this notice.
    case busy
    /// The input device went away mid-recording. What was captured before is kept and goes on to be transcribed.
    case deviceDisconnected
    /// The recording is digital silence, so the microphone looks muted or disconnected, and nothing is transcribed.
    case silentMicrophone
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
    /// The recording could not be written to disk and verified, so it was not transcribed. The text is the reason.
    case persistenceFailed(String)

    public enum Stage: Sendable, Equatable {
        case readiness
        case capture
        case transcription
        case insertion
    }

    /// The name of the case, without the text it carries, which can come from the system or from what was said. Logs
    /// use this and never the error itself.
    public var kind: String {
        switch self {
        case .microphoneNotGranted: "microphoneNotGranted"
        case .recognizerNotInstalled: "recognizerNotInstalled"
        case .recognizerUnavailable: "recognizerUnavailable"
        case .captureFailed: "captureFailed"
        case .recognitionFailed: "recognitionFailed"
        case .timedOut(let stage): "timedOut.\(stage)"
        case .notInserted(let reason): "notInserted.\(reason)"
        case .persistenceFailed: "persistenceFailed"
        }
    }

    public var remedy: Remedy {
        switch self {
        case .microphoneNotGranted: .permissions
        case .recognizerNotInstalled: .settings
        case .recognizerUnavailable(_, let retryable): retryable ? .retry : .settings
        case .captureFailed, .persistenceFailed, .recognitionFailed, .timedOut, .notInserted: .retry
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
    /// Returns once every insertion that has already returned has also finished its own clean-up, such as putting the
    /// user's clipboard back. The coordinator waits for this when it shuts down, so quitting does not leave a
    /// dictation on the clipboard. An inserter with nothing to clean up returns at once.
    func drain() async
}
