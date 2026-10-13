/// What a colored atom is for. Each case is a role and the theme says what color it has, so a status dot is never
/// "green", it is "success".
public nonisolated enum Tint: CaseIterable, Sendable {
    case neutral, accent, recording, success, warning, error

    /// The color of a dot, the fill of a bar, and the text of a pill in this tint.
    var color: ColorToken {
        switch self {
        case .neutral: .textSecondary
        case .accent: .accentPrimary
        case .recording: .accentRecording
        case .success: .statusSuccess
        case .warning: .statusWarning
        case .error: .statusError
        }
    }
}
