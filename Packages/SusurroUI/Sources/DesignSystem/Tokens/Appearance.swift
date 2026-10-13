public nonisolated enum Appearance: Sendable, Equatable {
    case light, dark
}

/// What the user chose for light and dark: follow the system, or always use one.
public nonisolated enum AppearanceOverride: Sendable, Equatable {
    case system, light, dark

    /// The appearance to show, given the one the system is in.
    public func appearance(whenSystemIs system: Appearance) -> Appearance {
        switch self {
        case .system: system
        case .light: .light
        case .dark: .dark
        }
    }
}
