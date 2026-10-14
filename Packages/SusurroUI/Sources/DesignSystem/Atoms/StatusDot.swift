import SwiftUI

/// A small filled circle in the color of its tint. With no `label` it is decoration and VoiceOver skips it.
public struct StatusDot: View {
    @Environment(\.theme) private var theme
    private let tint: Tint
    private let label: String?

    public init(_ tint: Tint, label: String? = nil) {
        self.tint = tint
        self.label = label
    }

    public var body: some View {
        Circle()
            .fill(theme.swiftUIColor(tint.color))
            .frame(width: theme.size(.statusDot), height: theme.size(.statusDot))
            .described(by: label)
    }
}

#Preview("StatusDot") { PreviewMatrix { StatusDot.Gallery() } }
