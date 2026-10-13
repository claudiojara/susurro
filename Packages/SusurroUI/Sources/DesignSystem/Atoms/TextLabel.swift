import SwiftUI

/// Text in one of the theme's type roles and colors. Named `TextLabel` so that it does not hide SwiftUI's `Label`.
public struct TextLabel: View {
    @Environment(\.theme) private var theme
    private let text: String
    private let style: TypeToken
    private let color: ColorToken

    public init(_ text: String, style: TypeToken = .body, color: ColorToken = .textPrimary) {
        self.text = text
        self.style = style
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(theme.font(style))
            .foregroundStyle(theme.swiftUIColor(color))
    }
}

#Preview("TextLabel") { PreviewMatrix { TextLabel.Gallery() } }
