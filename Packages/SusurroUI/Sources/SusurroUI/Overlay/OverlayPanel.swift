import AppKit
import SwiftUI

/// The window of the overlay: a borderless panel that never takes focus from the app the user is dictating into, shows on
/// every Space and over full-screen apps, and lets every click through.
public final class OverlayPanel: NSPanel {
    public init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}

/// Holds an `OverlayPanel` and the SwiftUI content in it. The content brings its own theme (the caller puts it in the
/// environment), so a theme that changes redraws it. The host decides nothing about what is shown or where: it sizes the
/// panel to the content, puts it at the frame it is given, and shows or hides it without ever making it key.
public final class OverlayPanelHost<Content: View> {
    public let panel = OverlayPanel()
    private let hosting: NSHostingView<Content>

    public init(content: Content) {
        hosting = NSHostingView(rootView: content)
        panel.contentView = hosting
    }

    public var isVisible: Bool { panel.isVisible }

    /// The size the content needs. It has a fixed width, so the height is that of its text at that width.
    public var fittingSize: CGSize { hosting.fittingSize }

    /// Puts the panel at `frame` and shows it. The panel is never made key: it must not take focus from the app being
    /// dictated into.
    public func present(at frame: CGRect) {
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    public func hide() {
        panel.orderOut(nil)
    }
}
