import DesignSystem
import SwiftUI

/// A shortcut drawn as key caps, one for each key, such as `⌃` `⌥` `D`. VoiceOver reads the keys in a row.
struct ShortcutBadge: View {
    @Environment(\.theme) private var theme
    private let keys: [String]

    init(_ keys: [String]) {
        self.keys = keys
    }

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                cap(key)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined(separator: " "))
    }

    private func cap(_ key: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius(.sm), style: .continuous)
        return Text(key)
            .font(theme.font(.mono))
            .foregroundStyle(theme.swiftUIColor(.textPrimary))
            .padding(.horizontal, theme.spacing(.sm))
            .padding(.vertical, theme.spacing(.xs))
            .background(theme.swiftUIColor(.surfaceRaised), in: shape)
            .overlay(shape.strokeBorder(theme.swiftUIColor(.borderSubtle)))
    }
}

#Preview("ShortcutBadge") { PreviewMatrix { ShortcutBadge.Gallery() } }
