import DesignSystem
import SwiftUI

/// A message on a raised card with the buttons that answer it: the question before something is deleted, and the error of
/// something that failed. `tint` colors the icon and the message.
struct HistoryNotice: View {
    struct Button: Identifiable {
        let title: String
        let kind: ActionButton.Kind
        let action: () -> Void
        var id: String { title }
    }

    @Environment(\.theme) private var theme
    private let message: String
    private let symbol: String
    private let tint: Tint
    private let buttons: [Button]

    init(_ message: String, symbol: String, tint: Tint, buttons: [Button]) {
        self.message = message
        self.symbol = symbol
        self.tint = tint
        self.buttons = buttons
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.sm)) {
            HStack(alignment: .top, spacing: theme.spacing(.sm)) {
                Icon(symbol, tint: tint)
                TextLabel(message, tint: tint)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: theme.spacing(.sm)) {
                ForEach(buttons) { button in
                    ActionButton(button.title, kind: button.kind, action: button.action)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

#Preview("HistoryNotice") { PreviewMatrix { HistoryNotice.Gallery() } }
