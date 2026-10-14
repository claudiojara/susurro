/// The name of one value a theme defines. Each kind of token is an enum, and its cases are the names a theme file must
/// define, so adding a token means adding a case here and a value in `DefaultTheme.json`.
public nonisolated protocol ThemeToken: RawRepresentable, CaseIterable, Hashable, Sendable where RawValue == String {
    /// The key of the group that holds these tokens in a theme file, such as `spacing`.
    static var group: String { get }
}

nonisolated extension ThemeToken {
    /// The token as `group.name`, the form the catalog and error messages use.
    var key: String { "\(Self.group).\(rawValue)" }
}

/// What a color is for, never what it looks like. A theme maps each one to a palette entry.
public nonisolated enum ColorToken: String, ThemeToken {
    case surfaceWindow = "surface.window"
    case surfaceRaised = "surface.raised"
    case surfaceOverlay = "surface.overlay"
    case surfaceTrack = "surface.track"
    case textPrimary = "text.primary"
    case textSecondary = "text.secondary"
    case textOnAccent = "text.onAccent"
    case accentPrimary = "accent.primary"
    case accentRecording = "accent.recording"
    case statusSuccess = "status.success"
    case statusWarning = "status.warning"
    case statusError = "status.error"
    case statePressed = "state.pressed"
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

/// The fixed dimension of a component, in points: what an atom is made of that is neither a gap between things nor a
/// corner. A component asks for its own size, so a theme can change the space between things without resizing a dot.
public nonisolated enum SizeToken: String, ThemeToken {
    /// The diameter of a status dot.
    case statusDot
    /// The thickness of a level bar.
    case levelBar
    /// The width of the onboarding screen.
    case onboardingWidth

    public static var group: String { "sizes" }
}

/// Durations in seconds, and the two numbers that shape the standard spring.
public nonisolated enum MotionToken: String, ThemeToken {
    case fast, standard, slow, springResponse, springDamping

    public static var group: String { "motion" }
}

/// The motion tokens that are seconds. An animation that takes a duration takes this, so the numbers of the spring
/// cannot be passed as one.
public nonisolated enum DurationToken: CaseIterable, Sendable {
    case fast, standard, slow

    public var token: MotionToken {
        switch self {
        case .fast: .fast
        case .standard: .standard
        case .slow: .slow
        }
    }
}
