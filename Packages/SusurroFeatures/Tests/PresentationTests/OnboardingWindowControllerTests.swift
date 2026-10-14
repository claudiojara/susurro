import AppKit
import CoreTestSupport
import DesignSystem
import Domain
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

    private func makeController(
        _ statuses: [Permission: PermissionStatus] = [.microphone: .denied, .accessibility: .denied],
        activations: Activations = Activations()
    ) -> OnboardingWindowController {
        let rig = Rig(statuses)
        return OnboardingWindowController(
            model: OnboardingViewModel(monitor: rig.monitor), themes: ThemeModel(),
            activate: { activations.count += 1 })
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

    @Test("the window is as wide as the onboarding width of the theme and fits the screen's content")
    func windowSize() throws {
        let controller = makeController()

        controller.window.contentView?.layoutSubtreeIfNeeded()
        let content = controller.window.contentLayoutRect

        #expect(content.width == (try Theme.default.resolved(for: .light)).size(.onboardingWidth))
        #expect(content.height > 300)
        #expect(content.height < 900)
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

    @Test("showing it again brings it forward again and does not move it")
    func showTwice() {
        let activations = Activations()
        let controller = makeController(activations: activations)
        controller.show()
        defer { controller.close() }
        controller.window.setFrameOrigin(NSPoint(x: 123, y: 456))

        controller.show()

        #expect(activations.count == 2)
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

    @Test("the screen is drawn in the theme model's theme")
    func screenFollowsTheTheme() {
        let rig = Rig([.microphone: .granted, .accessibility: .granted])
        let themes = ThemeModel()
        let controller = OnboardingWindowController(
            model: OnboardingViewModel(monitor: rig.monitor), themes: themes, activate: {})

        #expect(controller.content.themes === themes)
    }
}
