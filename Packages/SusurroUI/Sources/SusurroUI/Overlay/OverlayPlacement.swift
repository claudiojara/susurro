import CoreGraphics
import DesignSystem

/// A screen as the placement sees it, in the coordinates of AppKit (the origin is at the bottom left of the main screen).
public nonisolated struct OverlayScreen: Equatable, Sendable {
    public let frame: CGRect
    /// The part of the screen that is not under the menu bar or the Dock.
    public let visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

/// Where the overlay goes. It is pure, so it is tested without a window; the numbers come from the theme's overlay
/// geometry and the user's choice of edge.
public nonisolated enum OverlayPlacement {
    /// A frame is centered by leaving half of the spare room on each side.
    private static let sidesToCenterOn = 2

    /// The edge the overlay sits on. The user's choice wins; the theme says where it goes for a user who has not chosen.
    public static func edge(preference: ScreenEdge?, theme: OverlayGeometry) -> ScreenEdge {
        preference ?? theme.edge
    }

    /// The screen that holds most of the focused window, or `main` when there is no focused window or it is on none of
    /// the screens.
    public static func screen(
        containing focusedWindow: CGRect?, in screens: [OverlayScreen], main: OverlayScreen
    ) -> OverlayScreen {
        guard let focusedWindow else { return main }
        var best: (screen: OverlayScreen, area: CGFloat)?
        for screen in screens {
            let overlap = screen.frame.intersection(focusedWindow)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > (best?.area ?? 0) { best = (screen, area) }
        }
        return best?.screen ?? main
    }

    /// The frame of an overlay of `size`: horizontally centered on the screen of the focused window, `geometry.offset`
    /// from the top or the bottom of its visible area, and no wider than it.
    public static func frame(
        size: CGSize,
        geometry: OverlayGeometry,
        edgePreference: ScreenEdge? = nil,
        focusedWindow: CGRect?,
        screens: [OverlayScreen],
        main: OverlayScreen
    ) -> CGRect {
        let visible = screen(containing: focusedWindow, in: screens, main: main).visibleFrame
        let width = min(size.width, visible.width)
        let offset = CGFloat(geometry.offset)
        let y =
            switch edge(preference: edgePreference, theme: geometry) {
            case .bottom: visible.minY + offset
            case .top: visible.maxY - offset - size.height
            }
        return CGRect(x: visible.midX - width / CGFloat(Self.sidesToCenterOn), y: y, width: width, height: size.height)
    }

    /// Converts the bounds of a window as the window server reports them (the origin is at the top left of the main
    /// screen, and y grows downward) to the coordinates of AppKit. `mainScreenHeight` is the height of the main screen.
    public static func appKitRect(fromWindowServer bounds: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        CGRect(x: bounds.minX, y: mainScreenHeight - bounds.maxY, width: bounds.width, height: bounds.height)
    }
}
