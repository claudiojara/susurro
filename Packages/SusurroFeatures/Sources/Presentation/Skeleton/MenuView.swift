import Domain
import SwiftUI

/// The contents of the menu bar menu, in system styling: why dictation is off when it is, with the item that sets Susurro
/// up, the hotkey, one row for each required permission, the speech model, and Quit. A permission that is not granted has
/// an item that opens the matching pane of System Settings. The view knows nothing of the model or the application: it
/// shows `content`, and what its items do is passed in.
struct MenuView: View {
    let content: MenuContent
    let onSetUp: () -> Void
    let onOpenSettings: (Permission) -> Void
    let onQuit: () -> Void

    var body: some View {
        if let message = content.disabledMessage {
            Text(message)
            if let title = content.setUpTitle { Button(title, action: onSetUp) }
            Divider()
        }
        Text(content.hotkeyHint)
        Divider()
        permissionRows(content.microphone)
        permissionRows(content.accessibility)
        Divider()
        Text(content.modelLine)
        Divider()
        Button("Quit Susurro", action: onQuit)
            .keyboardShortcut("q")
    }

    @ViewBuilder
    private func permissionRows(_ row: MenuContent.PermissionRow) -> some View {
        Text(row.title)
        if let action = row.settingsActionTitle {
            Button(action) { onOpenSettings(row.permission) }
        }
    }
}
