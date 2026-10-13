/// The name of one value a theme defines. Each kind of token is an enum, and its cases are the names a theme file must
/// define, so adding a token means adding a case here and a value in `DefaultTheme.json`.
public nonisolated protocol ThemeToken: RawRepresentable, CaseIterable, Hashable, Sendable where RawValue == String {
    /// The key of the group that holds these tokens in a theme file, such as `spacing`.
    static var group: String { get }
}

/// What a color is for, never what it looks like. A theme maps each one to a palette entry.
public nonisolated enum ColorToken: String, ThemeToken {
    case surfaceWindow = "surface.window"
    case surfaceRaised = "surface.raised"
    case surfaceOverlay = "surface.overlay"
    case textPrimary = "text.primary"
    case textSecondary = "text.secondary"
    case textOnAccent = "text.onAccent"
    case accentPrimary = "accent.primary"
    case accentRecording = "accent.recording"
    case statusSuccess = "status.success"
    case statusWarning = "status.warning"
    case statusError = "status.error"
    case borderSubtle = "border.subtle"

    public static var group: String { "colors" }
}

/// A role in the type scale.
public nonisolated enum TypeToken: String, ThemeToken {
    case caption, body, bodyEmphasized, headline, title, mono

    public static var group: String { "typography" }
}

public nonisolated enum SpacingToken: String, ThemeToken {
    case xs, sm, md, lg, xl

    public static var group: String { "spacing" }
}

public nonisolated enum RadiusToken: String, ThemeToken {
    case sm, md, lg

    public static var group: String { "radii" }
}

/// Durations in seconds, and the two numbers that shape the standard spring.
public nonisolated enum MotionToken: String, ThemeToken {
    case fast, standard, slow, springResponse, springDamping

    public static var group: String { "motion" }
}
