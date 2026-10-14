import DesignSystem
import SwiftUI

/// A warning that the user has to read: an icon and a message that wraps, in the warning color, on a raised card. It is as
/// wide as the space it is given.
struct Banner: View {
    @Environment(\.theme) private var theme
    private let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing(.sm)) {
            Icon("exclamationmark.triangle.fill", tint: .warning)
            TextLabel(message, tint: .warning)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .card()
    }
}

#Preview("Banner") { PreviewMatrix { Banner.Gallery() } }
