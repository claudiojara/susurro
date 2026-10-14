import DesignSystem
import SwiftUI

/// A switch with a title and a line that says what it does. It is a plain button with a box that is filled when it is on,
/// so it draws the same on every machine, and VoiceOver reads it as a switch with its value.
struct SettingsToggle: View {
    @Environment(\.theme) private var theme
    private let title: String
    private let detail: String?
    private let isOn: Bool
    private let onChange: (Bool) -> Void

    init(_ title: String, detail: String? = nil, isOn: Bool, onChange: @escaping (Bool) -> Void) {
        self.title = title
        self.detail = detail
        self.isOn = isOn
        self.onChange = onChange
    }

    var body: some View {
        Button {
            onChange(!isOn)
        } label: {
            HStack(alignment: .top, spacing: theme.spacing(.sm)) {
                Icon(isOn ? "checkmark.square.fill" : "square", style: .headline, tint: isOn ? .accent : .neutral)
                VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                    TextLabel(title)
                    if let detail { TextLabel(detail, style: .caption, tint: .neutral) }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? L10n.string("toggle.on", "On") : L10n.string("toggle.off", "Off"))
    }
}

#Preview("SettingsToggle") { PreviewMatrix { SettingsToggle.Gallery() } }
