/// Why a dictation was written with its raw transcript although cleanup was on. The raw value is what the history
/// stores.
public enum FallbackReason: String, Sendable, Equatable, CaseIterable {
    /// The cleaner returned nothing once sanitized.
    case emptyOutput = "empty-output"
    /// The output reads like an assistant talking (a refusal, "the user is asking") and the transcript does not.
    case assistantMarker = "assistant-marker"
    /// The output is much longer than the transcript: the model answered instead of cleaning.
    case expansion
    /// The output is much shorter than the transcript: the model dropped most of it.
    case contraction
    /// The cleaner threw.
    case providerFailure = "provider-failure"
    /// The cleaner reported itself unavailable, so it was not called.
    case providerUnavailable = "provider-unavailable"
    /// The cleaner did not answer within its limit.
    case timeout
    /// The transcript is longer than the cleaner can take, so it was not called.
    case inputTooLarge = "input-too-large"
    /// The cleaner's safety system refused the text.
    case guardrail
}

extension FallbackReason {
    /// The reason for an error a cleaner threw. A guardrail refusal and an input that does not fit have reasons of
    /// their own; anything else, an `unavailable` throw included, is a provider failure.
    public init(thrownBy error: any Error) {
        switch error as? CleanerError {
        case .guardrail: self = .guardrail
        case .contextWindowExceeded: self = .inputTooLarge
        case .unavailable, .failed, nil: self = .providerFailure
        }
    }
}
