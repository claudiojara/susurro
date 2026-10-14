import SwiftUI

/// Text in one of the theme's type roles, in the plain text color or in the color of a tint. Named `TextLabel` so that
/// it does not hide SwiftUI's `Label`.
public struct TextLabel: View {
    @Environment(\.theme) private var theme
    private let text: String
    private let style: TypeToken
    private let tint: Tint?

    public init(_ text: String, style: TypeToken = .body, tint: Tint? = nil) {
        self.text = text
        self.style = style
        self.tint = tint
    }

    public var body: some View {
        Text(text)
            .font(theme.font(style))
            .foregroundStyle(theme.swiftUIColor(tint.textColor))
            // A label takes the lines its text needs at the width it is given. A stack that is a little short on height
            // would otherwise cut a wrapped label to one line, with an ellipsis.
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("TextLabel") { PreviewMatrix { TextLabel.Gallery() } }
