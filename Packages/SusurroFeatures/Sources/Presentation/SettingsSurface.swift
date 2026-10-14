import DesignSystem

/// Where the settings are shown: a window in the app, a recorder in a test.
@MainActor
public protocol SettingsSurface {
    /// Puts the settings in front of the user, and brings the app forward if it is not.
    func show()
}

/// The theme store as the settings use it: they list its themes and pick one.
extension ThemeStore: ThemeSelecting {}
