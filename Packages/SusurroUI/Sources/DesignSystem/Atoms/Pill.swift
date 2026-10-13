import SwiftUI

/// A short status in a capsule: the text takes the color of its tint.
public struct Pill: View {
    @Environment(\.theme) private var theme
    private let text: String
    private let tint: Tint

    public init(_ text: String, tint: Tint = .neutral) {
        self.text = text
        self.tint = tint
    }

    public var body: some View {
        TextLabel(text, style: .caption, tint: tint)
            .padding(.horizontal, theme.spacing(.sm))
            .padding(.vertical, theme.spacing(.xs))
            .background(theme.swiftUIColor(.surfaceRaised), in: Capsule())
            .overlay(Capsule().strokeBorder(theme.swiftUIColor(.borderSubtle)))
    }
}

#Preview("Pill") { PreviewMatrix { Pill.Gallery() } }
