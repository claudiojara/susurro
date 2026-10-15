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
    /// The paste landed but the user's old clipboard was not put back, because the snapshot of it was incomplete.
    /// `reason` is a fixed name such as "typeWithoutData" or "tooLarge".
    case clipboardNotRestored(reason: String)
    /// The style chosen for a dictation: the names of its category, tone, and the rule that decided. Nothing of the
    /// context it was chosen from is recorded.
    case styleResolved(category: String, tone: String, source: String)
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
    /// A setting was not saved because its value has no stored form. `key` is the storage name of the setting's key; the
    /// value is never recorded.
    case settingNotStored(key: String)
    /// A setting held something that does not read as the type of its key, so its default was used. `key` is the
    /// storage name of the setting's key; what it held is never recorded. It is recorded each time the key is read,
    /// until the key is set or removed.
    case settingUnreadable(key: String)
    /// A read of a permission's status differs from the one before. `from` is nil the first time the permission is read.
    /// A change from granted is a revocation. Only the permission and its status are recorded.
    case permissionStatusChanged(permission: Permission, from: PermissionStatus?, to: PermissionStatus)
    /// The permission stayed as it was long after the user was sent to System Settings, so the troubleshooting steps for
    /// it were shown.
    case permissionGuidanceShown(permission: Permission)
    /// A request to the system for the permission returned, and a read after it found the permission in `status`.
    case permissionRequestEnded(permission: Permission, status: PermissionStatus)
    /// A recording was written and read back. `id` names the file (`<id>.caf`) and `milliseconds` is its length.
    case recordingVerified(id: String, milliseconds: Int)
    /// A recording could not be written or verified. `step` is one of "begin", "write", or "verify".
    case recordingStoreFailed(step: String)
    /// A step of the durable pipeline could not reach the history. `step` is one of "insert" or "update". The
    /// dictation goes on without the record.
    case historyWriteFailed(step: String)
    /// The voice activity detector failed, so the recording went to the recognizer whole.
    case voiceDetectionFailed
    /// The recognizer answered in a language other than the one that was asked for, so the clip was transcribed again.
    case languageDriftDetected
    /// The key store could not be read for an account. Only the account and the system's status code are recorded: never
    /// a key, and never a message that could quote one.
    case secretUnreadable(account: SecretAccount, status: Int32)
    /// A request to a cloud provider failed. `reason` is a fixed word such as "http-401", "timeout", "network", or
    /// "response": never the body of the response and never anything that was sent.
    case cloudRequestFailed(provider: String, reason: String)
    /// The microphone the user chose is not connected, so the recording used the system default. The device is not
    /// named.
    case microphoneFallback
    /// The microphone the user chose is connected but could not be selected, so the recording used the system default.
    /// `status` is the CoreAudio status code.
    case microphoneSelectionFailed(status: Int32)
    /// Media that was playing was paused as a recording started (`paused` true), or resumed as it ended.
    case mediaPlayback(paused: Bool)
    /// A command replaced nothing. `reason` is a fixed name such as "timedOut", "unchanged", or "emptyOutput": never the
    /// instruction, the selection, or the reply.
    case commandNoResult(reason: String)
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
