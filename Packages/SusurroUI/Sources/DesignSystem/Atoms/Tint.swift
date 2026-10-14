/// What a colored atom is for. Each case is a role and the theme says what color it has, so a status dot is never
/// "green", it is "success". Every atom that has a color takes a `Tint`: text and icons take an optional one, where
/// nil is the plain color of text, and a button takes a `Kind` instead, because its fill, its text, and its border are
/// a fixed set for each kind.
public nonisolated enum Tint: CaseIterable, Sendable {
    case neutral, accent, recording, success, warning, error, pending

    /// The color of a dot, the fill of a bar, and the text of a pill in this tint.
    var color: ColorToken {
        switch self {
        case .neutral: .textSecondary
        case .accent: .accentPrimary
        case .recording: .accentRecording
        case .success: .statusSuccess
        case .warning: .statusWarning
        case .error: .statusError
        case .pending: .statusPending
        }
    }
}

extension Tint? {
    /// The color of text or an icon: the tint's, or the plain text color when there is no tint.
    var textColor: ColorToken { self?.color ?? .textPrimary }
}
