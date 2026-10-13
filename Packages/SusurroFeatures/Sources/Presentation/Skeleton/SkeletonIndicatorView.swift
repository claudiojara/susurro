import SwiftUI

/// The indicator, in system styling. There is no theme in the skeleton: 2e replaces this with themed views.
struct SkeletonIndicatorView: View {
    let indicator: OverlayIndicator?

    var body: some View {
        if let indicator {
            HStack(spacing: Layout.spacing) {
                Image(systemName: indicator.symbol)
                    .foregroundStyle(Self.color(for: indicator.tone))
                VStack(alignment: .leading, spacing: Layout.spacing / 2) {
                    Text(indicator.message)
                        .fixedSize(horizontal: false, vertical: true)
                    if let progress = indicator.progress {
                        ProgressView(value: progress)
                    }
                }
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.vertical, Layout.verticalPadding)
            // A fixed width, so that a long message wraps to the height the panel is given. With a flexible width the
            // panel is sized for one long line and the message is cut off.
            .frame(width: Layout.width)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Layout.cornerRadius))
        }
    }

    private enum Layout {
        static let spacing: CGFloat = 10
        static let horizontalPadding: CGFloat = 16
        static let verticalPadding: CGFloat = 10
        static let width: CGFloat = 380
        static let cornerRadius: CGFloat = 16
    }

    private static func color(for tone: OverlayIndicator.Tone) -> Color {
        switch tone {
        case .neutral: .secondary
        case .recording, .error: .red
        case .success: .green
        case .warning: .orange
        }
    }
}
