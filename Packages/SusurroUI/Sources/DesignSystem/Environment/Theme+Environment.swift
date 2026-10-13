import SwiftUI

extension EnvironmentValues {
    /// The theme that views take their colors, type, spacing, radii, and motion from. Set it with
    /// `View.themed(_:override:)`. Without a provider it is the bundled theme in light appearance.
    @Entry public var theme: ResolvedTheme = .standard
}
