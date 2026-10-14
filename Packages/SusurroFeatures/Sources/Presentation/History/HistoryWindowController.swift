import AppKit
import DesignSystem
import SusurroUI
import SwiftUI

/// Where the history is shown: a window in the app, a recorder in a test.
@MainActor
public protocol HistorySurface {
    /// Puts the history in front of the user, and brings the app forward if it is not.
    func show()
}

/// What the history window holds: the container over the view model, in the theme of the theme model. A change of the
/// theme redraws it, because the theme model is observable.
struct HistoryWindowContent: View {
    let model: HistoryViewModel
    let themes: ThemeModel

    var body: some View {
        HistoryContainer(model: model)
            .themed(themes.theme)
    }
}

/// The window of the history: a titled window that can be closed, resized, and minimized, opened from the menu. This is the
/// AppKit glue: what it shows is decided by the screen and the view model, which are tested.
@MainActor
public final class HistoryWindowController: HistorySurface {
    /// The size the window opens at, in points. A window is not a theme token: the user resizes it, and it remembers the
    /// size they chose.
    private static let openingSize = CGSize(width: 600, height: 680)
    private static let smallestSize = CGSize(width: 480, height: 360)
    private static let defaultFrameName = "SusurroHistoryWindow"

    let window: NSWindow
    private let host: NSHostingController<HistoryWindowContent>
    private let activate: @MainActor () -> Void
    /// Whether the system gave the window the frame the user left it at.
    private let wasRestored: Bool
    private var hasBeenPlaced = false

    public convenience init(model: HistoryViewModel, themes: ThemeModel) {
        self.init(model: model, themes: themes, activate: { NSApplication.shared.activate() })
    }

    /// - Parameters:
    ///   - activate: Brings the app forward. Tests pass a recorder, since a test process is no app to bring.
    ///   - frameName: The name the window's frame is saved under. Tests pass one of their own, so that a run does not
    ///     restore the frame an earlier run left.
    init(
        model: HistoryViewModel, themes: ThemeModel, activate: @escaping @MainActor () -> Void,
        frameName: String = HistoryWindowController.defaultFrameName
    ) {
        self.activate = activate
        host = NSHostingController(rootView: HistoryWindowContent(model: model, themes: themes))
        // The window is as big as the user makes it, not as big as its content.
        host.sizingOptions = []
        window = NSWindow(contentViewController: host)
        let window = window
        followLanguage { window.title = HistoryCopy.title }
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.contentMinSize = Self.smallestSize
        wasRestored = window.setFrameUsingName(frameName)
        window.setFrameAutosaveName(frameName)
    }

    public func show() {
        placeIfNeeded()
        activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Sizes and centers the window the first time, unless the system restored the frame the user left it at.
    private func placeIfNeeded() {
        guard !hasBeenPlaced else { return }
        hasBeenPlaced = true
        guard !wasRestored else { return }
        window.setContentSize(Self.openingSize)
        window.center()
    }

    func close() {
        window.close()
    }
}
