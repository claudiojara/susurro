import Domain

/// What the missing required permissions cost the user: Microphone missing turns dictation off, and Accessibility
/// missing sends the transcript to the clipboard instead of pasting it. The onboarding, the menu and the overlay show it
/// from this one type, so they cannot say different things. A conditional permission is never in it.
public struct DictationRestriction: Equatable, Sendable {
    /// The missing required permissions, in the order they were given (the order of the onboarding). Never empty.
    public let missing: [Permission]

    /// The restriction for a list of missing permissions, or nil when no required permission is in it and nothing is
    /// lost. A conditional permission in the list is left out: it leaves only its own feature inactive.
    init?(missing permissions: [Permission]) {
        let required = permissions.filter(PermissionPolicy.required.contains)
        guard !required.isEmpty else { return nil }
        missing = required
    }

    /// What the user reads: a sentence for each cost, Microphone first because it is the bigger one.
    public var message: String {
        var sentences: [String] = []
        if missing.contains(.microphone) { sentences.append("Dictation is off until Microphone is allowed.") }
        if missing.contains(.accessibility) {
            sentences.append("Dictated text goes to the clipboard until Accessibility is allowed.")
        }
        return sentences.joined(separator: " ")
    }
}

extension Permission {
    /// The name the user knows the permission by, as System Settings shows it.
    var displayName: String {
        switch self {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        case .screenRecording: "Screen Recording"
        }
    }
}
