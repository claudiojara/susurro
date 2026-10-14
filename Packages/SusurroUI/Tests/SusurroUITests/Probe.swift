import SwiftUI
import UITestSupport

@testable import DesignSystem

/// Reads what a view paints, for the tests of the onboarding views. A snapshot lets a tenth of a percent of its pixels
/// differ, so the colors and the parts of a view are checked on the pixels and on the size, as `AtomColorTests` does for
/// the atoms.
@MainActor
enum Probe {
    /// A channel of a painted pixel is one of 256 values, so it is within half a step of the token.
    static let exact = 1.0 / 255

    nonisolated static let schemes: [ColorScheme] = [.light, .dark]

    static func theme(_ scheme: ColorScheme, of theme: Theme = .default) throws -> ResolvedTheme {
        try theme.resolved(for: scheme == .dark ? .dark : .light)
    }

    static func picture(
        of view: some View, size: CGSize, scheme: ColorScheme, theme: Theme = .default
    ) -> CGImage {
        SnapshotSupport.cgImage(of: view, size: size, theme: theme, scheme: scheme)
    }

    /// Whether some pixel of the picture has the color, to within a step of a channel.
    static func isPainted(_ color: RGBAColor, in image: CGImage, region: CGRect? = nil) -> Bool {
        SnapshotSupport.closestDistance(in: image, to: color, region: region) <= exact
    }

    /// The height a view takes when it is given `width` and as much height as it needs, in points.
    static func height(
        of view: some View, width: CGFloat, scheme: ColorScheme = .light, theme: Theme = .default
    ) -> CGFloat {
        SnapshotSupport.idealSize(of: view.frame(width: width), theme: theme, scheme: scheme).height
    }

    /// The default theme with one radius changed.
    static func rounded(_ token: RadiusToken, _ points: Double) -> Theme {
        var theme = Theme.default
        theme.radii[token.rawValue] = points
        return theme
    }

    /// The default theme with one number of a scale changed.
    static func spaced(_ token: SpacingToken, _ points: Double) -> Theme {
        var theme = Theme.default
        theme.spacing[token.rawValue] = points
        return theme
    }
}

extension ColorScheme {
    /// The name a picture has in its file.
    var pictureName: String { self == .dark ? "dark" : "light" }
}
