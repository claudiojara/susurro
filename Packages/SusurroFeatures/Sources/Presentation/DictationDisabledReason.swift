import Domain

/// Why dictation is off: the required permissions that are not granted. The onboarding, the menu and the overlay show
/// it from this one type, so they cannot say different things. A conditional permission is never in it.
public struct DictationDisabledReason: Equatable, Sendable {
    /// The missing required permissions, in the order of the onboarding. Never empty.
    public let permissions: [Permission]

    /// The reason for a list of missing required permissions, or nil when it is empty and nothing holds dictation back.
    init?(blocking permissions: [Permission]) {
        guard !permissions.isEmpty else { return nil }
        self.permissions = permissions
    }

    /// What the user reads, naming each missing permission.
    public var message: String {
        let names = permissions.map(\.displayName).joined(separator: " and ")
        return "Dictation is off until \(names) \(permissions.count == 1 ? "is" : "are") allowed."
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
