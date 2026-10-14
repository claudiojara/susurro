import DesignSystem
import SwiftUI

/// A row of choices, one picked: each is a chip, and the picked one is filled in the accent. Chips are plain buttons, so
/// the control draws the same on every machine. It wraps when the choices do not fit.
struct ChoiceChips: View {
    @Environment(\.theme) private var theme
    private let choices: [SettingsChoice]
    private let selected: String
    private let label: String
    private let onSelect: (String) -> Void

    /// - Parameter label: What VoiceOver calls the group.
    init(_ choices: [SettingsChoice], selected: String, label: String, onSelect: @escaping (String) -> Void) {
        self.choices = choices
        self.selected = selected
        self.label = label
        self.onSelect = onSelect
    }

    var body: some View {
        FlowLayout(spacing: theme.spacing(.sm), lineSpacing: theme.spacing(.sm)) {
            ForEach(choices) { choice in
                chip(choice, isSelected: choice.id == selected)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func chip(_ choice: SettingsChoice, isSelected: Bool) -> some View {
        Button {
            onSelect(choice.id)
        } label: {
            Text(choice.title)
                .font(theme.font(isSelected ? .bodyEmphasized : .body))
                .foregroundStyle(theme.swiftUIColor(isSelected ? .textOnAccent : .textPrimary))
                .padding(.horizontal, theme.spacing(.md))
                .padding(.vertical, theme.spacing(.xs))
                .background(theme.swiftUIColor(isSelected ? .accentPrimary : .surfaceRaised), in: Capsule())
                .overlay(Capsule().strokeBorder(theme.swiftUIColor(.borderSubtle)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("ChoiceChips") { PreviewMatrix { ChoiceChips.Gallery() } }
