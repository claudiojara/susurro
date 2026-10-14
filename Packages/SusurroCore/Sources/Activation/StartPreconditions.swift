import Domain

/// What must hold before the microphone opens. The coordinator reads the three inputs and the machine receives the
/// result with the press, so the rule is pure.
public enum StartPreconditions {
    /// Whether the selected recognizer needs an API key and has one.
    public enum KeyRequirement: Sendable, Equatable {
        /// A local recognizer.
        case notRequired
        /// A cloud recognizer that is enabled and has its key.
        case present
        /// A cloud recognizer that is not enabled, or has no key.
        case missing
    }

    /// The error that stops the recording, which names the way out through `remedy`, or nil when it may start. The
    /// microphone is checked first, then the recognizer, then the key. A recognizer that is still loading does not stop
    /// anything: the clip waits for it.
    public static func evaluate(
        microphone: PermissionStatus, recognizer: RecognizerReadiness, key: KeyRequirement = .notRequired
    ) -> PipelineError? {
        guard microphone == .granted else { return .microphoneNotGranted }
        switch recognizer {
        case .notInstalled: return .recognizerNotInstalled
        case .unavailable(let reason, let retryable): return .recognizerUnavailable(reason, retryable: retryable)
        case .loading, .ready: break
        }
        return key == .missing ? .cloudKeyMissing : nil
    }
}
