/// Something worth a line in the log. The cases carry the names of things, never their content: no transcript, no audio,
/// and no text from an error, because an error can quote what the user said. Keep it that way when adding a case.
public enum DiagnosticEvent: Sendable, Equatable {
    /// A dictation ended in an error. `kind` is `PipelineError.kind`.
    case dictationFailed(kind: String)
    /// The capture stream failed while recording. The audio captured until then is kept. `errorType` is the name of the
    /// error's type.
    case captureStreamFailed(errorType: String)
    /// The total limit on processing one dictation ran out. It comes just before the `dictationFailed` event for the
    /// stage that was under way, which tells it apart from the limit of that stage alone running out.
    case processingCapReached
    /// The recording reached its time limit and was finished by it, not by the release of the key.
    case recordingCapReached
    /// The key of a hold that ran into the recording cap was still down when the wait for its release ran out, so the
    /// text was inserted anyway.
    case releaseWaitExpired
    /// A capture did not stop within its limit and was left behind.
    case captureStopAbandoned
    /// The inserter did not finish its clean-up before the shutdown gave up on it.
    case shutdownDrainAbandoned
    /// A paste did not land and the text was left on the clipboard, or is nowhere. `cause` is a fixed name such as
    /// "noRead" or "modifiersHeld".
    case pasteNotCompleted(cause: String)
    /// The pasteboard refused a write of the dictation.
    case pasteboardWriteRefused
    /// The pasteboard refused to take the user's old contents back.
    case clipboardRestoreFailed
    /// The app asked the inserter to put the clipboard back as it terminated. `restored` is false when there was
    /// nothing to put back: no paste was under way, or the user had copied something since.
    case clipboardRestoreAtTermination(restored: Bool)
    /// The first buffer the microphone tap delivered in a capture. Its size sets how soon the first chunk arrives.
    case captureFirstBuffer(frames: Int, sampleRate: Double)
    /// The app finished launching and started its work.
    case appLaunched
    /// The app is terminating.
    case appTerminating
    /// The app asked the speech recognizer to load its model.
    case modelPrepareRequested
    /// The speech model changed state. `state` is one of "loading", "ready", "unavailable", or "notInstalled".
    case modelReadiness(String)
    /// The status of the two required permissions once the launch prompts were answered. Each is "granted", "denied",
    /// or "notDetermined".
    case launchPermissions(microphone: String, accessibility: String)
}

/// Where the pipeline reports what it would otherwise swallow. The live log lives in the platform package.
public protocol DiagnosticsLog: Sendable {
    func record(_ event: DiagnosticEvent)
}

/// A log that keeps nothing, for callers that do not care.
public struct NoDiagnostics: DiagnosticsLog {
    public init() {}

    public func record(_ event: DiagnosticEvent) {}
}
