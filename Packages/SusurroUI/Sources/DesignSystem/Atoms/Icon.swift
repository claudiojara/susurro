import SwiftUI

/// A system symbol sized by a type role, so that it sits with the text beside it. An icon with no `label` is
/// decoration and VoiceOver skips it.
public struct Icon: View {
    @Environment(\.theme) private var theme
    private let systemName: String
    private let style: TypeToken
    private let color: ColorToken
    private let label: String?

    public init(
        _ systemName: String, style: TypeToken = .body, color: ColorToken = .textPrimary, label: String? = nil
    ) {
        self.systemName = systemName
        self.style = style
        self.color = color
        self.label = label
    }

    public var body: some View {
        Image(systemName: systemName)
            .font(theme.font(style))
            .foregroundStyle(theme.swiftUIColor(color))
            .described(by: label)
    }
}

#Preview("Icon") { PreviewMatrix { Icon.Gallery() } }
