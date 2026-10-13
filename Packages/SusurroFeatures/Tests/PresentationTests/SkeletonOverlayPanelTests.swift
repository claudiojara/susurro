import AppKit
import Testing

@testable import Presentation

@MainActor
@Suite("Skeleton overlay panel")
struct SkeletonOverlayPanelTests {
    @Test("the panel is borderless and non-activating, takes no key or main status, and ignores the mouse")
    func configuration() {
        let panel = SkeletonOverlayPanel()

        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.ignoresMouseEvents)
    }

    @Test("the panel joins every Space and shows over full-screen apps, above ordinary windows")
    func visibility() {
        let panel = SkeletonOverlayPanel()

        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.level == .statusBar)
        #expect(!panel.hidesOnDeactivate)
    }

    @Test("the panel has no background of its own, so only the indicator shows")
    func transparent() {
        let panel = SkeletonOverlayPanel()

        #expect(!panel.isOpaque)
        #expect(panel.backgroundColor == .clear)
    }

    @Test("showing the panel does not make it the key or main window")
    func showingTakesNoFocus() {
        let panel = SkeletonOverlayPanel()
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }

        #expect(!panel.isKeyWindow)
        #expect(!panel.isMainWindow)
    }
}

@Suite("Skeleton overlay placement")
struct SkeletonOverlayPlacementTests {
    private let size = CGSize(width: 320, height: 48)

    @Test("the panel is centered horizontally and sits 80 points above the bottom of the visible area")
    func bottomCenter() {
        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)

        #expect(SkeletonOverlayPlacement.frame(size: size, in: screen) == CGRect(x: 560, y: 80, width: 320, height: 48))
    }

    @Test("placement follows the visible area of a screen that is not at the origin, such as one above the Dock")
    func secondScreen() {
        let screen = CGRect(x: 1_440, y: 25, width: 1_920, height: 1_055)
        let wide = CGSize(width: 400, height: 60)

        #expect(
            SkeletonOverlayPlacement.frame(size: wide, in: screen) == CGRect(x: 2_200, y: 105, width: 400, height: 60))
    }

    @Test("a panel wider than the screen is narrowed to fit it")
    func clampsWidth() {
        let screen = CGRect(x: 100, y: 0, width: 300, height: 600)

        let frame = SkeletonOverlayPlacement.frame(size: CGSize(width: 500, height: 48), in: screen)

        #expect(frame == CGRect(x: 100, y: 80, width: 300, height: 48))
    }
}
