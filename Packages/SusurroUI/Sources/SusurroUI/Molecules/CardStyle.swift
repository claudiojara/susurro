import DesignSystem
import SwiftUI

/// The look the molecules share: a raised surface with a subtle border and rounded corners, with room inside.
private struct CardStyle: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        let card = RoundedRectangle(cornerRadius: theme.radius(.md), style: .continuous)
        content
            .padding(theme.spacing(.md))
            .background(theme.swiftUIColor(.surfaceRaised), in: card)
            .overlay(card.strokeBorder(theme.swiftUIColor(.borderSubtle)))
    }
}

extension View {
    /// Puts the view on a raised card. A card is as wide as the view inside it, so a view that should fill the width of
    /// its parent has to say so before it.
    func card() -> some View {
        modifier(CardStyle())
    }
}
