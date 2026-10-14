/// Which edge of the screen the overlay sits on. The theme has an edge too, and it is the default: a user who chose one
/// here gets it whatever the theme says, and a user who did not gets the theme's.
public enum OverlayEdgeSetting: String, Sendable, CaseIterable {
    case followTheme
    case top
    case bottom
}

/// The settings of the recording overlay, stored under `overlay.`.
public enum OverlaySettings {
    /// The id of the overlay variant, which the registry of the UI resolves. An id nobody registered falls back to the
    /// default variant with a reported error.
    public static let variant = SettingKey<String>(area: "overlay", name: "variant", default: "pill")
    public static let edge = SettingKey<OverlayEdgeSetting>(area: "overlay", name: "edge", default: .followTheme)

    public static let all: [any AnySettingKey] = [variant, edge]
}
