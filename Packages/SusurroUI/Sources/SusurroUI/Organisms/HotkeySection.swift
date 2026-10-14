import DesignSystem
import SwiftUI

/// The Hotkey tab: the shortcut that starts a dictation, the recorder that changes it, and the warnings that apply: a
/// modifier-only hotkey that needs Input Monitoring, and Secure Event Input. The recorder is a native control that the
/// app injects, since the UI package imports no platform module. A pure function of the state and the slot.
struct HotkeySection<Recorder: View>: View {
    @Environment(\.theme) private var theme
    private let state: HotkeySettingsState
    private let actions: HotkeyActions
    private let recorder: Recorder

    init(_ state: HotkeySettingsState, actions: HotkeyActions, @ViewBuilder recorder: () -> Recorder) {
        self.state = state
        self.actions = actions
        self.recorder = recorder()
    }

    var body: some View {
        VStack(spacing: theme.spacing(.md)) {
            if let warning = state.permissionWarning {
                VStack(alignment: .leading, spacing: theme.spacing(.sm)) {
                    Banner(warning.message)
                    if let title = warning.actionTitle {
                        ActionButton(title, kind: .primary, action: actions.requestInputMonitoring)
                    }
                }
            }
            if let message = state.secureInputWarning { Banner(message) }
            SettingsCard("Dictation hotkey", footer: Copy.footer) {
                HStack(spacing: theme.spacing(.md)) {
                    ShortcutBadge(state.shortcut)
                    TextLabel(Copy.hold, tint: .neutral)
                    Spacer(minLength: 0)
                }
                recorder
            }
        }
    }
}

private enum Copy {
    static let hold = "Hold to talk, release to insert."
    static let footer =
        "A shortcut with a regular key works without any permission. One made only of modifier keys, or the fn key, stays off until Input Monitoring is allowed."
}

#Preview("HotkeySection") { PreviewMatrix { HotkeySection<EmptyView>.Gallery() } }
