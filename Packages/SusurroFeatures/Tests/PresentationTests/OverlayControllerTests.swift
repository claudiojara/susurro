import AppKit
import CoreTestSupport
import DesignSystem
import Domain
import SusurroUI
import Testing

@testable import Presentation

@MainActor
@Suite("Overlay controller", .timeLimit(.minutes(1)))
struct OverlayControllerTests {
    private static let screen = OverlayScreen(
        frame: CGRect(x: 0, y: 0, width: 1_512, height: 949), visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 920))
    private static let second = OverlayScreen(
        frame: CGRect(x: 1_512, y: 0, width: 1_920, height: 1_080),
        visibleFrame: CGRect(x: 1_512, y: 0, width: 1_920, height: 1_055))

    @MainActor private struct Rig {
        let model = OverlayViewModel()
        let themes = ThemeModel()
        let controller: OverlayController

        init(focusedWindow: CGRect? = nil) {
            let model = model
            let themes = themes
            controller = OverlayController(
                model: model, themes: themes, registry: .standard(),
                screens: { [OverlayControllerTests.screen, OverlayControllerTests.second] },
                mainScreen: { OverlayControllerTests.screen }, focusedWindow: { focusedWindow })
            // The view model shows what it decides on the controller, as the app wires them.
            let controller = controller
            model.display = { controller.display($0) }
        }
    }

    /// Lets AppKit run its layout and display passes, which is when a hosting view resizes its window.
    private func letAppKitLayOut() async {
        try? await Task.sleep(for: .milliseconds(300))
    }

    private static let error = PipelineState.error(.microphoneNotGranted)
    private static let inserted = PipelineState.inserted

    @Test("the panel is as wide as the theme says, no taller than a few lines, and sits above the bottom edge")
    func panelHasASensibleFrame() async {
        let rig = Rig()
        defer { rig.controller.display(.hidden) }

        rig.model.apply(Self.error)
        await letAppKitLayOut()

        let frame = rig.controller.panelFrame
        #expect(frame.height > 20)
        #expect(frame.height < 150)
        #expect(frame.width == CGFloat(ThemeModel().theme.overlay.width))
        #expect(frame.minY == CGFloat(ThemeModel().theme.overlay.offset))
        #expect(abs(frame.midX - Self.screen.visibleFrame.midX) < 1)
    }

    @Test("a new state moves the panel to match it, and hiding takes the panel off the screen")
    func panelFollowsTheState() async {
        let rig = Rig()

        rig.model.apply(Self.inserted)
        await letAppKitLayOut()
        let short = rig.controller.panelFrame
        rig.model.apply(Self.error)  // an error replaces a held result at once
        await letAppKitLayOut()
        let tall = rig.controller.panelFrame
        let visibleWhileShown = rig.controller.isPanelVisible
        rig.controller.display(.hidden)

        #expect(short.height < tall.height)  // the error wraps to more lines than "Pasted"
        #expect(visibleWhileShown)
        #expect(!rig.controller.isPanelVisible)
    }

    @Test("the panel goes to the screen of the focused window")
    func followsTheFocusedWindow() async {
        let rig = Rig(focusedWindow: CGRect(x: 1_800, y: 100, width: 900, height: 700))
        defer { rig.controller.display(.hidden) }

        rig.model.apply(Self.inserted)
        await letAppKitLayOut()

        #expect(Self.second.frame.contains(rig.controller.panelFrame))
    }

    @Test("the edge the user chose wins over the theme's")
    func edgeSetting() async {
        let rig = Rig()
        defer { rig.controller.display(.hidden) }
        let settings = InMemorySettingsStore()
        settings.set(OverlayEdgeSetting.top, for: OverlaySettings.edge)
        rig.model.read(settings)

        rig.model.apply(Self.inserted)
        await letAppKitLayOut()

        let visible = Self.screen.visibleFrame
        #expect(rig.controller.panelFrame.maxY == visible.maxY - CGFloat(ThemeModel().theme.overlay.offset))
    }
}
