import DesignSystem
import SwiftUI

/// The Providers tab: the speech recognizers and the cleanup providers, the one in use marked in each list. A cloud
/// provider stays off until the user turns it on and adds a key to the Keychain. A pure function of the state.
struct ProvidersSection: View {
    @Environment(\.theme) private var theme
    private let state: ProvidersSettingsState
    private let actions: ProvidersActions

    init(_ state: ProvidersSettingsState, actions: ProvidersActions) {
        self.state = state
        self.actions = actions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.lg)) {
            group("Speech recognition", rows: state.speech, footer: Copy.speechFooter)
            group("Text cleanup", rows: state.cleanup, footer: Copy.cleanupFooter)
        }
    }

    private func group(_ title: String, rows: [ProviderRowState], footer: String) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.sm)) {
            TextLabel(title, style: .headline)
                .accessibilityAddTraits(.isHeader)
            ForEach(rows) { row in
                ProviderRow(
                    row, onSelect: { actions.select(row.id) }, onEnable: { actions.setEnabled(row.id, $0) },
                    onField: { actions.setField(row.id, $0, $1) })
            }
            TextLabel(footer, style: .caption, tint: .neutral)
        }
    }

    private enum Copy {
        static let speechFooter =
            "Audio stays on this Mac unless you turn on a cloud provider and choose it. Keys are read from your Keychain, service app.tuminuta, and never stored by Susurro."
        static let cleanupFooter =
            "A cloud cleanup provider receives the transcript, your dictionary words, the category, and the tone. It never receives the text around the cursor, the selection, or the screen."
    }
}

#Preview("ProvidersSection") { PreviewMatrix { ProvidersSection.Gallery() } }
