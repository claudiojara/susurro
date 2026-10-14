import AppKit
import SwiftUI
import Testing

@testable import SusurroUI

@MainActor
@Suite("Overlay panel")
struct OverlayPanelTests {
    @Test("the panel is borderless and non-activating, takes no key or main status, and ignores the mouse")
    func configuration() {
        let panel = OverlayPanel()

        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.ignoresMouseEvents)
    }

    @Test("the panel joins every Space and shows over full-screen apps, above ordinary windows")
    func visibility() {
        let panel = OverlayPanel()

        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.level == .statusBar)
        #expect(!panel.hidesOnDeactivate)
    }

    @Test("the panel has no background of its own, so only the overlay shows")
    func transparent() {
        let panel = OverlayPanel()

        #expect(!panel.isOpaque)
        #expect(panel.backgroundColor == .clear)
    }

    @Test("showing the panel does not make it the key or main window")
    func showingTakesNoFocus() {
        let host = OverlayPanelHost(content: Text("Listening…"))
        host.present(at: CGRect(x: 100, y: 100, width: 200, height: 40))
        defer { host.hide() }

        #expect(host.isVisible)
        #expect(!host.panel.isKeyWindow)
        #expect(!host.panel.isMainWindow)
    }

    @Test("the host puts the panel at the frame it is given, and hiding takes it off the screen")
    func presentAndHide() {
        let host = OverlayPanelHost(content: Text("Listening…"))
        let frame = CGRect(x: 120, y: 80, width: 240, height: 48)

        host.present(at: frame)
        let shown = host.panel.frame
        host.hide()

        #expect(shown == frame)
        #expect(!host.isVisible)
    }

    @Test("the host reports the size its content needs")
    func fittingSize() {
        let host = OverlayPanelHost(content: Text("Listening…"))

        #expect(host.fittingSize.width > 0)
        #expect(host.fittingSize.height > 0)
    }
}

@MainActor
@Suite("Focus preservation")
struct FocusPreservationTests {
    /// A test process with no window server session (some CI machines) has no frontmost application to look at.
    nonisolated private static var hasGraphicalSession: Bool { CGSessionCopyCurrentDictionary() != nil }

    /// Whether this process is the frontmost app. Another app can come to the front while a test runs, for reasons of its
    /// own, so the test does not compare the frontmost app before and after: it checks that showing the overlay never made
    /// the app that shows it the active one, which is what would take the focus from the app being dictated into.
    private static var thisProcessIsFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    @Test(
        "showing and hiding the overlay never makes its app the frontmost one",
        .enabled(if: hasGraphicalSession, "needs a graphical session"))
    func overlayNeverBecomesFrontmost() async {
        let host = OverlayPanelHost(content: Text("Listening…"))
        #expect(!Self.thisProcessIsFrontmost)

        host.present(at: CGRect(x: 100, y: 100, width: 200, height: 40))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(!Self.thisProcessIsFrontmost)
        #expect(!NSRunningApplication.current.isActive)
        #expect(!host.panel.isKeyWindow)

        host.hide()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(!Self.thisProcessIsFrontmost)
    }
}
