import DesignSystem
import SwiftUI

/// What the overlay shows for a state, as the default look draws it: a symbol, the words, a hint when the recording is
/// hands-free, the input level while recording, and a bar while the speech model loads. It is a pure function of the
/// state, the level, and the theme: it has no clock and reads no service. A hidden state draws nothing.
struct OverlayHUD: View {
    @Environment(\.theme) private var theme
    private let state: OverlayViewState
    private let level: Double

    init(state: OverlayViewState, level: Double = 0) {
        self.state = state
        self.level = level
    }

    var body: some View {
        if let text = state.text, let symbol = state.symbol {
            let shape = RoundedRectangle(cornerRadius: theme.overlay.cornerRadius, style: .continuous)
            HStack(alignment: .top, spacing: theme.spacing(.md)) {
                Icon(symbol, style: .headline, tint: state.tint)
                VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                    TextLabel(text, style: .bodyEmphasized)
                        .fixedSize(horizontal: false, vertical: true)
                    details
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, theme.spacing(.lg))
            .padding(.vertical, theme.spacing(.md))
            // A fixed width, so that a long message wraps to the height the panel is given. With a flexible width the
            // panel is sized for one long line and the message is cut off.
            .frame(width: theme.overlay.width, alignment: .leading)
            .background(theme.swiftUIColor(.surfaceOverlay), in: shape)
            .overlay(shape.strokeBorder(theme.swiftUIColor(.borderSubtle)))
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var details: some View {
        switch state {
        case .recording(_, let text, let hint):
            WaveformMeter(level: level, label: text)
            if let hint {
                TextLabel(hint, style: .caption, tint: .neutral)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .transcribing(let text, let progress?):
            LevelBar(level: progress, tint: .accent, label: text)
        case .hidden, .starting, .transcribing, .polishing, .inserted, .notice, .error:
            EmptyView()
        }
    }
}
