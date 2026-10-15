import DesignSystem
import SwiftUI

extension EnvironmentValues {
    /// Draws text inputs as plain text on a field, with no live editing. A snapshot sets it, because the system text field
    /// is a native control that the renderer of snapshots cannot draw.
    @Entry var staticControls = false
}

/// A text input in the look of the theme, one line unless it is multi-line. It edits a copy of the value and hands the
/// result over when the user presses Return or leaves the field, so a half-typed address is never stored. A multi-line
/// input grows with its text; Option-Return starts a new line in it.
struct TextInput: View {
    @Environment(\.theme) private var theme
    @Environment(\.staticControls) private var isStatic
    @FocusState private var isFocused: Bool
    @State private var draft: String
    private let label: String
    private let value: String
    private let placeholder: String
    private let hasError: Bool
    private let commitsWhileTyping: Bool
    private let isMultiline: Bool
    private let onCommit: (String) -> Void

    /// - Parameters:
    ///   - label: What VoiceOver calls the field.
    ///   - commitsWhileTyping: Hands every change over at once, for the field of a form that is read when a button is
    ///     pressed, since pressing a button does not take the focus from the field.
    ///   - isMultiline: Takes several lines, such as the text of a snippet.
    init(
        _ label: String, value: String, placeholder: String = "", hasError: Bool = false,
        commitsWhileTyping: Bool = false, isMultiline: Bool = false, onCommit: @escaping (String) -> Void
    ) {
        self.label = label
        self.value = value
        self.placeholder = placeholder
        self.hasError = hasError
        self.commitsWhileTyping = commitsWhileTyping
        self.isMultiline = isMultiline
        self.onCommit = onCommit
        _draft = State(initialValue: value)
    }

    var body: some View {
        field
            .padding(.horizontal, theme.spacing(.sm))
            .padding(.vertical, theme.spacing(.xs))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.swiftUIColor(.surfaceWindow), in: shape)
            .overlay(shape.strokeBorder(theme.swiftUIColor(hasError ? .statusError : .borderSubtle)))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.radius(.sm), style: .continuous)
    }

    @ViewBuilder
    private var field: some View {
        if isStatic {
            Text(value.isEmpty ? placeholder : value)
                .font(theme.font(.body))
                .foregroundStyle(theme.swiftUIColor(value.isEmpty ? .textSecondary : .textPrimary))
                .lineLimit(isMultiline ? nil : 1)
                .accessibilityLabel(label)
        } else {
            TextField(label, text: $draft, prompt: Text(placeholder), axis: isMultiline ? .vertical : .horizontal)
                .textFieldStyle(.plain)
                .font(theme.font(.body))
                .foregroundStyle(theme.swiftUIColor(.textPrimary))
                .focused($isFocused)
                .onSubmit { onCommit(draft) }
                .onChange(of: isFocused) { _, focused in
                    if !focused, draft != value { onCommit(draft) }
                }
                .onChange(of: draft) { _, new in
                    if commitsWhileTyping { onCommit(new) }
                }
                .onChange(of: value) { _, new in draft = new }
        }
    }
}

#Preview("TextInput") { PreviewMatrix { TextInput.Gallery() } }
