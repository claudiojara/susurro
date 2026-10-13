/// Something worth a line in the log. The cases carry the names of things, never their content: no transcript, no audio,
/// and no text from an error, because an error can quote what the user said. Keep it that way when adding a case.
public enum DiagnosticEvent: Sendable, Equatable {
    /// A dictation ended in an error. `kind` is `PipelineError.kind`.
    case dictationFailed(kind: String)
    /// The capture stream failed while recording. The audio captured until then is kept. `errorType` is the name of the
    /// error's type.
    case captureStreamFailed(errorType: String)
    /// A capture did not stop within its limit and was left behind.
    case captureStopAbandoned
    /// The inserter did not finish its clean-up before the shutdown gave up on it.
    case shutdownDrainAbandoned
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
