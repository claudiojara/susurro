import AppKit
import CoreTestSupport
import DesignSystem
import Domain
import SwiftUI
import Testing

@testable import Presentation

/// The window is AppKit glue: what the onboarding shows and when it opens are decided by the presenter and the screen,
/// which are tested. These tests check the window itself: its kind, its size from the theme, and that it opens, comes
/// forward, and closes.
@MainActor
@Suite("Onboarding window controller", .timeLimit(.minutes(1)))
struct OnboardingWindowControllerTests {
    private final class Activations {
        var count = 0
    }

    private static let screen = CGRect(x: 0, y: 0, width: 1_512, height: 949)

    private func makeController(
        _ statuses: [Permission: PermissionStatus] = [.microphone: .denied, .accessibility: .denied],
        activations: Activations = Activations()
    ) -> OnboardingWindowController {
        let rig = Rig(statuses)
        return OnboardingWindowController(
            model: OnboardingViewModel(monitor: rig.monitor), themes: ThemeModel(),
            activate: { activations.count += 1 }, visibleFrame: { Self.screen })
    }

    @Test("the window is titled and can be closed, and it cannot be resized or minimized")
    func windowKind() {
        let controller = makeController()

        #expect(controller.window.title == "Set up Susurro")
        #expect(controller.window.styleMask.contains(.titled))
        #expect(controller.window.styleMask.contains(.closable))
        #expect(!controller.window.styleMask.contains(.resizable))
        #expect(!controller.window.styleMask.contains(.miniaturizable))
        #expect(!controller.window.isReleasedWhenClosed)
    }

    @Test("the window is as wide as the onboarding width of the theme and as tall as the screen's content")
    func windowSize() throws {
        let controller = makeController()
        controller.show()
        defer { controller.close() }

        let content = controller.window.contentLayoutRect

        #expect(content.width == (try Theme.default.resolved(for: .light)).size(.onboardingWidth))
        #expect(content.height > 300)
        #expect(content.height < 900)
    }

    @Test("a window with more rows is taller, and its top edge stays where it was")
    func windowGrowsWithTheContent() async throws {
        let rig = Rig([.microphone: .granted, .accessibility: .granted])
        let controller = OnboardingWindowController(
            model: OnboardingViewModel(monitor: rig.monitor), themes: ThemeModel(), activate: {},
            visibleFrame: { Self.screen })
        await rig.monitor.refresh()
        controller.show()
        defer { controller.close() }
        let before = controller.window.frame

        await rig.monitor.setNeeds(PermissionNeeds(modifierOnlyHotkey: true, ocrEnabled: true))
        // SwiftUI redraws on the next turn of the run loop, which is when the hosting controller resizes the window.
        await waitUntil { controller.window.frame.height > before.height || !controller.window.isVisible }

        #expect(controller.window.frame.height > before.height + 100)  // two optional rows
        #expect(controller.window.frame.maxY == before.maxY)
    }

    @Test("showing the window brings the app forward and puts the window on the screen, key")
    func showBringsItForward() {
        let activations = Activations()
        let controller = makeController(activations: activations)

        controller.show()
        defer { controller.close() }

        #expect(activations.count == 1)
        #expect(controller.window.isVisible)
        #expect(controller.window.isKeyWindow || controller.window.canBecomeKey)
    }

    @Test("showing it again brings it forward again")
    func showTwice() {
        let activations = Activations()
        let controller = makeController(activations: activations)

        controller.show()
        defer { controller.close() }
        controller.show()

        #expect(activations.count == 2)
        #expect(controller.window.isVisible)
    }

    @Test("it is placed the first time, and where the user moved it after that")
    func placedOnce() {
        let controller = makeController()
        controller.placeIfNeeded()
        let placed = controller.window.frame.origin
        controller.window.setFrameOrigin(NSPoint(x: 123, y: 456))

        controller.placeIfNeeded()

        #expect(placed != NSPoint(x: 123, y: 456))
        #expect(controller.window.frame.origin == NSPoint(x: 123, y: 456))
    }

    @Test("closing takes the window off the screen, and it can be shown again")
    func closeAndShowAgain() {
        let controller = makeController()
        controller.show()

        controller.close()
        let closed = !controller.window.isVisible
        controller.show()
        let shownAgain = controller.window.isVisible
        controller.close()

        #expect(closed)
        #expect(shownAgain)
    }

    @Test("the Done button of the screen closes the window")
    func doneCloses() {
        let controller = makeController()
        controller.show()

        controller.content.onDone()

        #expect(!controller.window.isVisible)
    }

    @Test("the screen is drawn in the theme model's theme: another accent repaints the buttons")
    func screenFollowsTheTheme() {
        let magenta = ThemeLoader.load(
            data: Data(
                #"""
                {"schemaVersion": 1, "palette": {"magenta": {"light": "#FF00FF", "dark": "#FF00FF"}},
                 "colors": {"accent.primary": "magenta"}}
                """#.utf8))
        func picture(of theme: Theme) -> Data {
            let rig = Rig([.microphone: .denied, .accessibility: .denied])
            let controller = OnboardingWindowController(
                model: OnboardingViewModel(monitor: rig.monitor), themes: ThemeModel(theme: theme), activate: {},
                visibleFrame: { Self.screen })
            let renderer = ImageRenderer(content: controller.content)
            return renderer.nsImage?.tiffRepresentation ?? Data()
        }

        let bundled = picture(of: .default)
        let repainted = picture(of: magenta.theme)

        let differing = zip(bundled, repainted).filter { $0 != $1 }.count
        #expect(magenta.errors.isEmpty)
        #expect(bundled.count == repainted.count && bundled.count > 1_000)
        #expect(differing > 1_000, "\(differing) bytes differ")  // the two request buttons are about 300 by 40 points
    }

    // MARK: Placement

    @Test("the window is placed centered across the screen, in its upper part")
    func opensInTheUpperMiddle() {
        let controller = makeController()
        controller.placeIfNeeded()

        let frame = controller.window.frame

        #expect(frame.size.width == (try? Theme.default.resolved(for: .light).size(.onboardingWidth)))
        #expect(abs(frame.midX - Self.screen.midX) < 1)
        #expect(frame.maxY < Self.screen.maxY)
        #expect(frame.minY > Self.screen.minY)
        #expect(frame.maxY > Self.screen.midY + frame.height / 2 - 1)  // above the middle
    }

    @Test(
        "the window is centered across the area and a third of the room left over sits above it",
        arguments: [
            (CGSize(width: 440, height: 400), CGRect(x: 0, y: 0, width: 1_000, height: 700), CGPoint(x: 280, y: 200)),
            (
                CGSize(width: 400, height: 300), CGRect(x: 100, y: 50, width: 1_200, height: 900),
                CGPoint(x: 500, y: 450)
            ),
            // Too tall for the area: the top edge stays at the top of the area, and the rest hangs below.
            (CGSize(width: 440, height: 800), CGRect(x: 0, y: 0, width: 1_000, height: 700), CGPoint(x: 280, y: -100)),
        ])
    func placement(size: CGSize, area: CGRect, origin: CGPoint) {
        #expect(OnboardingWindowController.origin(of: size, in: area) == origin)
    }
}
