import DesignSystem
import SwiftUI

/// A small pill: the symbol of the state and, while recording, the input level and nothing else. The other states say
/// what they are in a word, and a notice or an error keeps its whole sentence, since the overlay cannot be clicked and
/// the sentence is the way out.
public struct MinimalOverlayStyle: OverlayStyle {
    public static let id = "minimal"

    public init() {}

    public func body(state: OverlayViewState, level: Double) -> AnyView {
        AnyView(MinimalOverlayHUD(state: state, level: level))
    }
}

/// What the minimal style draws. A pure function of the state, the level, and the theme.
struct MinimalOverlayHUD: View {
    @Environment(\.theme) private var theme
    let state: OverlayViewState
    let level: Double

    var body: some View {
        if let text = state.text, let symbol = state.symbol {
            let shape = RoundedRectangle(cornerRadius: theme.radius(.lg), style: .continuous)
            HStack(spacing: theme.spacing(.sm)) {
                Icon(symbol, style: .body, tint: state.tint)
                content(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, theme.spacing(.md))
            .padding(.vertical, theme.spacing(.sm))
            .frame(width: theme.layout(.overlayCompactWidth))
            .background(theme.swiftUIColor(.surfaceOverlay), in: shape)
            .overlay(shape.strokeBorder(theme.swiftUIColor(.borderSubtle)))
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private func content(_ text: String) -> some View {
        switch state {
        case .recording:
            LevelBar(level: level, tint: .recording, label: text)
        case .transcribing(_, let progress?):
            LevelBar(level: progress, tint: .accent, label: text)
        case .notice, .error:
            TextLabel(text, style: .caption)
                .fixedSize(horizontal: false, vertical: true)
        case .hidden, .starting, .transcribing, .polishing, .inserted:
            TextLabel(text, style: .caption, tint: .neutral)
                .lineLimit(1)
        }
    }
}
