import SwiftUI

/// The menu bar menu wired to the app: it reads the content from the model and sends the items to the model and to the
/// application. The menu itself is `MenuView`.
public struct SkeletonMenuView: View {
    private let model: MenuModel

    public init(model: MenuModel) {
        self.model = model
    }

    public var body: some View {
        MenuView(
            content: model.content,
            onSetUp: { model.setUp() },
            onRequest: { permission in Task { await model.request(permission) } },
            onOpenSettings: { model.openSettings(for: $0) },
            onQuit: { NSApplication.shared.terminate(nil) },
            onShowHistory: { model.openHistory() }
        )
    }
}
