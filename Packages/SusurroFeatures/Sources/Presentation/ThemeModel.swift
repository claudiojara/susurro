import DesignSystem
import Observation

/// The theme the app's windows are drawn in. It follows what the theme store publishes, so a theme file that is edited or
/// chosen shows without a relaunch, and it keeps the errors of a file that could not be used, in which case the theme is
/// the bundled one. It is observable, so a view that reads `theme` is drawn again when it changes.
@MainActor
@Observable
public final class ThemeModel {
    public private(set) var theme: Theme
    /// What was wrong with the theme file in use, or nothing when it was used.
    public private(set) var errors: [ThemeError] = []

    public init(theme: Theme = .default) {
        self.theme = theme
    }

    /// Takes the theme of each result until the stream ends.
    public func follow(_ updates: AsyncStream<ThemeLoadResult>) async {
        for await result in updates {
            theme = result.theme
            errors = result.errors
        }
    }
}
