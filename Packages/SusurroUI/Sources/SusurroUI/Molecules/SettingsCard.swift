import DesignSystem
import SwiftUI

/// The block every settings tab is made of: a heading, the controls, and a line below them that explains. It fills the
/// width it is given.
struct SettingsCard<Content: View>: View {
    @Environment(\.theme) private var theme
    private let title: String
    private let footer: String?
    private let content: Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.md)) {
            TextLabel(title, style: .headline)
                .accessibilityAddTraits(.isHeader)
            content
            if let footer { TextLabel(footer, style: .caption, tint: .neutral) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

#Preview("SettingsCard") { PreviewMatrix { SettingsCardGallery() } }
