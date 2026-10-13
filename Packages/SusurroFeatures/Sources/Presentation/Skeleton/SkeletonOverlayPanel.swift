import AppKit

/// The window of the overlay: a borderless panel that never takes focus from the app the user is dictating into.
@MainActor
final class SkeletonOverlayPanel: NSPanel {
    init() {
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

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Where the panel goes. Until 2d moves it to the screen of the focused window, it is the main screen.
enum SkeletonOverlayPlacement {
    /// The gap between the bottom of the visible area (above the Dock) and the panel.
    static let bottomMargin: CGFloat = 80

    /// Horizontally centered in `visibleFrame`, `bottomMargin` above its bottom edge, and no wider than it.
    static func frame(size: CGSize, in visibleFrame: CGRect) -> CGRect {
        let width = min(size.width, visibleFrame.width)
        return CGRect(
            x: visibleFrame.minX + (visibleFrame.width - width) / 2,
            y: visibleFrame.minY + bottomMargin,
            width: width,
            height: size.height
        )
    }
}
