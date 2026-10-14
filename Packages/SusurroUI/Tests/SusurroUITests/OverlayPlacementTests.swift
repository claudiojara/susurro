import CoreGraphics
import Testing

@testable import DesignSystem
@testable import SusurroUI

@Suite("Overlay placement")
struct OverlayPlacementTests {
    private static let first = OverlayScreen(
        frame: CGRect(x: 0, y: 0, width: 1_440, height: 900), visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875))
    private static let second = OverlayScreen(
        frame: CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080),
        visibleFrame: CGRect(x: 1_440, y: 30, width: 1_920, height: 1_025))
    private static let screens = [first, second]
    private static let size = CGSize(width: 380, height: 60)
    private static let geometry = Theme.default.overlay

    private static func frame(
        focusedWindow: CGRect?, edgePreference: ScreenEdge? = nil, geometry: OverlayGeometry = geometry
    ) -> CGRect {
        OverlayPlacement.frame(
            size: size, geometry: geometry, edgePreference: edgePreference, focusedWindow: focusedWindow,
            screens: screens, main: first)
    }

    private static let windowOnSecond = CGRect(x: 1_700, y: 200, width: 900, height: 600)

    @Test("with the focused window on the second screen the frame is on the second screen, centered, at the bottom")
    func secondScreenBottom() {
        let frame = Self.frame(focusedWindow: Self.windowOnSecond)

        #expect(Self.second.frame.contains(frame))
        #expect(frame.midX == Self.second.visibleFrame.midX)
        #expect(frame.minY == Self.second.visibleFrame.minY + CGFloat(Self.geometry.offset))
        #expect(frame.size == Self.size)
    }

    @Test("the user can put the overlay at the top")
    func secondScreenTop() {
        let frame = Self.frame(focusedWindow: Self.windowOnSecond, edgePreference: .top)

        #expect(Self.second.frame.contains(frame))
        #expect(frame.maxY == Self.second.visibleFrame.maxY - CGFloat(Self.geometry.offset))
        #expect(frame.midX == Self.second.visibleFrame.midX)
    }

    @Test("without a focused window the main screen is used")
    func mainScreenFallback() {
        let frame = Self.frame(focusedWindow: nil)

        #expect(Self.first.frame.contains(frame))
        #expect(frame.midX == Self.first.visibleFrame.midX)
    }

    @Test("a window on none of the screens, or on the first, gives the main screen and the first screen")
    func windowOffScreen() {
        let nowhere = CGRect(x: 9_000, y: 9_000, width: 100, height: 100)

        #expect(Self.first.frame.contains(Self.frame(focusedWindow: nowhere)))
        #expect(Self.first.frame.contains(Self.frame(focusedWindow: CGRect(x: 100, y: 100, width: 300, height: 300))))
    }

    @Test("a window that spans two screens counts for the one that holds most of it")
    func spanningWindow() {
        let mostlyOnSecond = CGRect(x: 1_340, y: 100, width: 800, height: 500)  // 100 points on the first screen
        let mostlyOnFirst = CGRect(x: 640, y: 100, width: 900, height: 500)  // 100 points on the second screen

        #expect(Self.second.frame.contains(Self.frame(focusedWindow: mostlyOnSecond)))
        #expect(Self.first.frame.contains(Self.frame(focusedWindow: mostlyOnFirst)))
    }

    @Test("the geometry comes from the theme: its offset moves the overlay and its width limits it")
    func geometryFromTheTheme() {
        var theme = Theme.default
        theme.overlay.offset = 40
        let frame = Self.frame(focusedWindow: Self.windowOnSecond, geometry: theme.overlay)
        let narrow = OverlayPlacement.frame(
            size: CGSize(width: 5_000, height: 60), geometry: Self.geometry, focusedWindow: Self.windowOnSecond,
            screens: Self.screens, main: Self.first)

        #expect(frame.minY == Self.second.visibleFrame.minY + 40)
        #expect(narrow.width == Self.second.visibleFrame.width)  // wider than the screen: narrowed to fit it
    }

    @Test("the user's edge wins over the theme's, and the theme's edge is the default")
    func edgeSettingWins() {
        var bottom = Theme.default.overlay
        bottom.edge = .bottom
        var top = bottom
        top.edge = .top

        #expect(OverlayPlacement.edge(preference: nil, theme: bottom) == .bottom)
        #expect(OverlayPlacement.edge(preference: nil, theme: top) == .top)
        #expect(OverlayPlacement.edge(preference: .top, theme: bottom) == .top)
        #expect(OverlayPlacement.edge(preference: .bottom, theme: top) == .bottom)
        // The frame follows: a theme at the top still gives the bottom to a user who chose it.
        let frame = OverlayPlacement.frame(
            size: Self.size, geometry: top, edgePreference: .bottom, focusedWindow: nil, screens: Self.screens,
            main: Self.first)
        #expect(frame.minY == Self.first.visibleFrame.minY + CGFloat(top.offset))
    }

    @Test("the bounds of a window from the window server are flipped to the coordinates of AppKit")
    func windowServerBounds() {
        let bounds = CGRect(x: 100, y: 50, width: 800, height: 600)

        let rect = OverlayPlacement.appKitRect(fromWindowServer: bounds, mainScreenHeight: 900)

        #expect(rect == CGRect(x: 100, y: 250, width: 800, height: 600))
    }
}
