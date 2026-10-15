import DesignSystem
import SwiftUI

/// The command mode card of the Hotkey tab: the switch that turns it on, the shortcut that is held over selected text,
/// and the recorder that changes it. The recorder is a slot that the app fills with `HotkeyRecorderContainer`, as for the
/// dictation hotkey. A pure function of the state and the slot.
struct CommandModeSection<Recorder: View>: View {
    @Environment(\.theme) private var theme
    private let state: CommandModeSettingsState
    private let actions: CommandModeActions
    private let recorder: Recorder

    init(_ state: CommandModeSettingsState, actions: CommandModeActions, @ViewBuilder recorder: () -> Recorder) {
        self.state = state
        self.actions = actions
        self.recorder = recorder()
    }

    var body: some View {
        VStack(spacing: theme.spacing(.md)) {
            if let warning = state.warning { Banner(warning) }
            if let warning = state.permissionWarning {
                VStack(alignment: .leading, spacing: theme.spacing(.sm)) {
                    Banner(warning.message)
                    if let title = warning.actionTitle {
                        ActionButton(title, kind: .primary, action: actions.requestInputMonitoring)
                    }
                }
            }
            SettingsCard(Copy.title, footer: Copy.footer) {
                SettingsToggle(Copy.toggle, detail: Copy.detail, isOn: state.isEnabled, onChange: actions.setEnabled)
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
    static var title: String { L10n.string("command.title", "Command mode") }
    static var toggle: String { L10n.string("command.toggle", "Rewrite the selection by voice") }
    static var detail: String {
        L10n.string("command.detail", "Apple Intelligence rewrites it on this Mac. It takes a few seconds.")
    }
    static var hold: String {
        L10n.string("command.hold", "Select text, hold, and say what to do, such as \u{201C}make it formal\u{201D}.")
    }
    static var footer: String {
        L10n.string(
            "command.footer",
            "The result replaces the selection, and Command-Z brings it back. Esc cancels. The selection is never stored."
        )
    }
}

#Preview("CommandModeSection") { PreviewMatrix { CommandModeSection<EmptyView>.Gallery() } }
