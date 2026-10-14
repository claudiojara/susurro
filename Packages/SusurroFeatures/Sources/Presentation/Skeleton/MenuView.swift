import Domain
import SwiftUI

/// The contents of the menu bar menu, in system styling: what a missing permission costs when one is missing, with the
/// item that sets Susurro up, the hotkey, one row for each required permission, the speech model, and Quit. A permission that is not granted has
/// an item for the step that fits it: allow it, or open the matching pane of System Settings. The view knows nothing of the model or the application: it
/// shows `content`, and what its items do is passed in.
struct MenuView: View {
    let content: MenuContent
    let onSetUp: () -> Void
    let onRequest: (Permission) -> Void
    let onOpenSettings: (Permission) -> Void
    let onQuit: () -> Void
    /// Opens the settings. With none, the menu has no Settings item.
    var onSettings: (() -> Void)?

    var body: some View {
        if let message = content.restrictionMessage {
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
        if let onSettings {
            Button("Settings…", action: onSettings)
                .keyboardShortcut(",")
        }
        Button("Quit Susurro", action: onQuit)
            .keyboardShortcut("q")
    }

    @ViewBuilder
    private func permissionRows(_ row: MenuContent.PermissionRow) -> some View {
        Text(row.title)
        if let action = row.action {
            Button(action.title) {
                Self.perform(action, for: row.permission, onRequest: onRequest, onOpenSettings: onOpenSettings)
            }
        }
    }

    /// Sends the step of an item to the handler of its kind. A static function, so a test can call it without a menu.
    static func perform(
        _ action: MenuContent.PermissionRow.Action, for permission: Permission,
        onRequest: (Permission) -> Void, onOpenSettings: (Permission) -> Void
    ) {
        switch action.kind {
        case .request: onRequest(permission)
        case .openSettings: onOpenSettings(permission)
        }
    }
}
