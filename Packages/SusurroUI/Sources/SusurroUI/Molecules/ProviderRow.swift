import DesignSystem
import SwiftUI

/// One provider in the settings: which one is in use, where it runs, how it stands, the switch of a cloud provider that
/// has to be turned on, whether its key is in the Keychain, and the values the user types for it. It is a pure function
/// of the row and the theme: what the controls do is passed in. The key itself is never part of the row.
struct ProviderRow: View {
    @Environment(\.theme) private var theme
    private let row: ProviderRowState
    private let onSelect: () -> Void
    private let onEnable: (Bool) -> Void
    private let onField: (String, String) -> Void

    init(
        _ row: ProviderRowState, onSelect: @escaping () -> Void, onEnable: @escaping (Bool) -> Void,
        onField: @escaping (String, String) -> Void
    ) {
        self.row = row
        self.onSelect = onSelect
        self.onEnable = onEnable
        self.onField = onField
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.sm)) {
            header
            HStack(spacing: theme.spacing(.sm)) {
                StatusDot(row.status.level.tint)
                TextLabel(row.status.text, style: .caption, tint: row.status.level.tint)
            }
            .accessibilityElement(children: .combine)
            if let isEnabled = row.isEnabled {
                SettingsToggle("Turn on \(row.title)", isOn: isEnabled, onChange: onEnable)
            }
            if let key = row.key {
                TextLabel(key.note, style: .caption, tint: key.isPresent ? .success : .neutral)
            }
            ForEach(row.fields) { field in
                fieldView(field)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var header: some View {
        HStack(spacing: theme.spacing(.sm)) {
            Button(action: onSelect) {
                HStack(spacing: theme.spacing(.sm)) {
                    Icon(
                        row.isSelected ? "largecircle.fill.circle" : "circle", style: .headline,
                        tint: row.isSelected ? .accent : .neutral)
                    TextLabel(row.title, style: .headline)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(row.isSelected ? .isSelected : [])
            .accessibilityHint("Use this provider")
            Spacer(minLength: theme.spacing(.sm))
            Pill(row.locality, tint: row.isCloud ? .warning : .neutral)
        }
    }

    @ViewBuilder
    private func fieldView(_ field: ProviderFieldState) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            TextLabel(field.label, style: .caption, tint: .neutral)
            if field.choices.isEmpty {
                TextInput(
                    field.label, value: field.value, placeholder: field.placeholder, hasError: field.error != nil
                ) { onField(field.id, $0) }
            } else {
                ChoiceChips(field.choices, selected: field.value, label: field.label) { onField(field.id, $0) }
            }
            if let error = field.error { TextLabel(error, style: .caption, tint: .error) }
        }
    }
}

extension ProviderStatusState.Level {
    /// The tint of the status dot and its text.
    var tint: Tint {
        switch self {
        case .ready: .success
        case .pending: .pending
        case .warning: .warning
        case .error: .error
        }
    }
}

#Preview("ProviderRow") { PreviewMatrix { ProviderRow.Gallery() } }
