import Foundation

/// Contrast as WCAG 2 defines it, for checking that text can be read on what it is drawn on.
nonisolated extension RGBAColor {
    /// The relative luminance of the color, from 0 for black to 1 for white: the sRGB components made linear and
    /// weighted by how much the eye gets from each.
    var relativeLuminance: Double {
        func linear(_ component: Double) -> Double {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// The contrast ratio between this color, as it looks painted over `background`, and `background`: 1 for the same
    /// color, up to 21 for black and white, and the same whichever is the text. The background must be opaque: paint
    /// a translucent one over what is behind it first (`composited(over:)`). WCAG AA asks for 4.5 for the text of the
    /// type roles, which are all below 18 pt.
    public func contrastRatio(against background: RGBAColor) -> Double {
        let seen = composited(over: background).relativeLuminance
        let behind = background.relativeLuminance
        return (max(seen, behind) + 0.05) / (min(seen, behind) + 0.05)
    }
}
