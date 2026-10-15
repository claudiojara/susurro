import DesignSystem
import SwiftUI

/// The card of the Hotkey tab for the shortcut that pastes the last dictation: the shortcut, or that there is none, and
/// the recorder that changes it, a slot the app fills as it does for the dictation hotkey. A pure function of the state
/// and the slot.
struct PasteLastSection<Recorder: View>: View {
    @Environment(\.theme) private var theme
    private let state: PasteLastSettingsState
    private let recorder: Recorder

    init(_ state: PasteLastSettingsState, @ViewBuilder recorder: () -> Recorder) {
        self.state = state
        self.recorder = recorder()
    }

    var body: some View {
        SettingsCard(Copy.title, footer: Copy.footer) {
            HStack(spacing: theme.spacing(.md)) {
                if state.shortcut.isEmpty {
                    TextLabel(Copy.unassigned, tint: .neutral)
                } else {
                    ShortcutBadge(state.shortcut)
                    TextLabel(Copy.press, tint: .neutral)
                }
                Spacer(minLength: 0)
            }
            recorder
        }
    }

    private enum Copy {
        static var title: String { L10n.string("pasteLast.title", "Paste last dictation") }
        static var press: String { L10n.string("pasteLast.press", "Press to paste it again.") }
        static var unassigned: String { L10n.string("pasteLast.unassigned", "No shortcut") }
        static var footer: String {
            L10n.string(
                "pasteLast.footer",
                "Pastes the text of your most recent dictation where the cursor is. The menu can also copy it.")
        }
    }
}

#Preview("PasteLastSection") { PreviewMatrix { PasteLastSection<EmptyView>.Gallery() } }
