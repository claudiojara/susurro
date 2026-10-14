import SwiftUI

/// Where a theme value becomes a SwiftUI one. This folder is the only part of the design system that the token lint
/// lets write `Color(` or `.system(size:`; a view asks the theme for its colors and fonts through these.
nonisolated extension RGBAColor {
    public var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

nonisolated extension TypeStyle {
    public var swiftUIFont: Font {
        .system(size: size, weight: weight.swiftUIWeight, design: design.swiftUIDesign)
    }
}

nonisolated extension TypeWeight {
    fileprivate var swiftUIWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

nonisolated extension TypeDesign {
    fileprivate var swiftUIDesign: Font.Design {
        switch self {
        case .standard: .default
        case .rounded: .rounded
        case .monospaced: .monospaced
        case .serif: .serif
        }
    }
}

nonisolated extension ResolvedTheme {
    public func swiftUIColor(_ token: ColorToken) -> Color {
        color(token).swiftUIColor
    }

    public func font(_ token: TypeToken) -> Font {
        type(token).swiftUIFont
    }

    /// An ease-in-out animation as long as a duration token (`fast`, `standard`, or `slow`), or none when motion is
    /// off, which is how a test gets one fixed picture.
    public func easing(_ token: MotionToken, motionEnabled: Bool) -> Animation? {
        motionEnabled ? .easeInOut(duration: motion(token)) : nil
    }
}
