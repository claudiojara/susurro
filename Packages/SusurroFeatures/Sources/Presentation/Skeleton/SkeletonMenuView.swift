import SwiftUI

/// The contents of the menu bar menu, in system styling: the hotkey, one row for each required permission, the speech
/// model, and Quit. A permission that is not granted has an item that opens the matching pane of System Settings.
public struct SkeletonMenuView: View {
    private let model: MenuModel

    public init(model: MenuModel) {
        self.model = model
    }

    public var body: some View {
        let content = model.content
        Text(content.hotkeyHint)
        Divider()
        permissionRows(content.microphone)
        permissionRows(content.accessibility)
        Divider()
        Text(content.modelLine)
        Divider()
        Button("Quit Susurro") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder
    private func permissionRows(_ row: MenuContent.PermissionRow) -> some View {
        Text(row.title)
        if let action = row.settingsActionTitle {
            Button(action) { model.openSettings(for: row.permission) }
        }
    }
}
