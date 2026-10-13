import SwiftUI

/// A button with a title: filled in the accent for the main action, quiet for the others, red for a destructive one.
public struct ActionButton: View {
    public enum Kind: CaseIterable, Sendable {
        case primary, secondary, destructive
    }

    private let title: String
    private let kind: Kind
    private let action: () -> Void

    public init(_ title: String, kind: Kind = .secondary, action: @escaping () -> Void) {
        self.title = title
        self.kind = kind
        self.action = action
    }

    public var body: some View {
        Button(action: action) { Text(title) }
            .buttonStyle(ActionButtonStyle(kind: kind))
    }
}

struct ActionButtonStyle: ButtonStyle {
    let kind: ActionButton.Kind

    func makeBody(configuration: Configuration) -> some View {
        ActionButtonFace(kind: kind, isPressed: configuration.isPressed) { configuration.label }
    }
}

/// What the button looks like. It is its own view so that a snapshot can show the pressed state, which SwiftUI
/// decides for itself in a live button. A disabled button is the quiet one with the secondary text color.
struct ActionButtonFace<Label: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.motionEnabled) private var motionEnabled
    private let kind: ActionButton.Kind
    private let isPressed: Bool
    private let label: Label

    init(kind: ActionButton.Kind, isPressed: Bool, @ViewBuilder label: () -> Label) {
        self.kind = kind
        self.isPressed = isPressed
        self.label = label()
    }

    private var colors: (fill: ColorToken, text: ColorToken, quiet: Bool) {
        guard isEnabled else { return (.surfaceRaised, .textSecondary, true) }
        switch kind {
        case .primary: return (.accentPrimary, .textOnAccent, false)
        case .secondary: return (.surfaceRaised, .textPrimary, true)
        case .destructive: return (.statusError, .textOnAccent, false)
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius(.md), style: .continuous)
        label
            .font(theme.font(.bodyEmphasized))
            .foregroundStyle(theme.swiftUIColor(colors.text))
            .padding(.horizontal, theme.spacing(.md))
            .padding(.vertical, theme.spacing(.sm))
            .background(theme.swiftUIColor(colors.fill), in: shape)
            .overlay { if colors.quiet { shape.strokeBorder(theme.swiftUIColor(.borderSubtle)) } }
            .overlay { if isPressed { shape.fill(theme.swiftUIColor(.statePressed)) } }
            .animation(theme.easing(.fast, motionEnabled: motionEnabled), value: isPressed)
    }
}

#Preview("ActionButton") { PreviewMatrix { ActionButton.Gallery() } }
