import DesignSystem
import SwiftUI

/// The control that changes the hotkey. At rest it offers a button to record a new shortcut, and another to bring the
/// default back when the shortcut is not the default. While it listens it shows a field with the modifier keys the user is
/// holding, as key caps, and a button to give up; a shortcut that is refused is told in a banner above, and the field goes
/// on listening. A pure function of the state and the actions: the keys are heard by the code behind it.
struct HotkeyRecorder: View {
    @Environment(\.theme) private var theme
    private let state: HotkeyRecorderState
    private let actions: HotkeyRecorderActions

    init(state: HotkeyRecorderState, actions: HotkeyRecorderActions) {
        self.state = state
        self.actions = actions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.md)) {
            if let rejection = state.rejection { Banner(rejection) }
            switch state.phase {
            case .idle: resting
            case .listening(let held): listening(held: held)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resting: some View {
        HStack(spacing: theme.spacing(.md)) {
            ActionButton(Copy.change, action: actions.begin)
            if state.canRestoreDefault {
                ActionButton(Copy.restore, action: actions.restoreDefault)
            }
            Spacer(minLength: 0)
        }
    }

    private func listening(held: [String]) -> some View {
        HStack(spacing: theme.spacing(.md)) {
            field(held: held)
            ActionButton(Copy.cancel, action: actions.cancel)
        }
    }

    /// The place where the keys show up, outlined in the accent so that it is plain that the next keys are heard.
    private func field(held: [String]) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius(.md), style: .continuous)
        return HStack(spacing: theme.spacing(.sm)) {
            ZStack(alignment: .leading) {
                // A key cap that is never seen, so that the field is as tall with the prompt as with the keys, and does
                // not grow when the user presses the first one.
                ShortcutBadge(["fn"]).hidden()
                if held.isEmpty {
                    TextLabel(Copy.prompt, tint: .neutral)
                } else {
                    ShortcutBadge(held)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(theme.spacing(.md))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.swiftUIColor(.surfaceWindow), in: shape)
        .overlay(shape.strokeBorder(theme.swiftUIColor(.accentPrimary)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(held.isEmpty ? Copy.prompt : held.joined(separator: " "))
    }
}

private enum Copy {
    static let change = "Change shortcut"
    static let restore = "Restore default"
    static let cancel = "Cancel"
    static let prompt = "Press the new shortcut, or Esc to cancel."
}

#Preview("HotkeyRecorder") { PreviewMatrix { HotkeyRecorder.Gallery() } }
