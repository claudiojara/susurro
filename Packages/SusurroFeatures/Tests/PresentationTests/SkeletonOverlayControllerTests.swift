import AppKit
import Domain
import Testing

@testable import Presentation

@MainActor
@Suite("Skeleton overlay controller", .timeLimit(.minutes(1)))
struct SkeletonOverlayControllerTests {
    private static let screen = CGRect(x: 0, y: 0, width: 1_512, height: 949)

    /// Lets AppKit run its layout and display passes, which is when a hosting view resizes its window.
    private func letAppKitLayOut() async {
        try? await Task.sleep(for: .milliseconds(300))
    }

    private func makeController() -> SkeletonOverlayController {
        SkeletonOverlayController(visibleFrame: { Self.screen })
    }

    @Test(
        "the panel is as wide as the indicator is, no taller than a few lines, and sits above the bottom edge",
        arguments: [
            OverlayIndicator.indicator(for: .recording(.hold))!,
            OverlayIndicator.modelLoading(progress: 0.42),
            OverlayIndicator.indicator(for: .error(.microphoneNotGranted))!,
        ]
    )
    func panelHasASensibleFrame(indicator: OverlayIndicator) async {
        let sut = makeController()

        sut.display(indicator)
        await letAppKitLayOut()

        let frame = sut.panelFrame
        #expect(frame.height > 20)
        #expect(frame.height < 150)
        #expect(frame.width == 380)  // one width for every message, so a long one wraps to the height it is given
        #expect(frame.minY == 80)  // the bottom margin, still there after layout
        #expect(abs(frame.midX - Self.screen.midX) < 1)
        sut.display(nil)
    }

    @Test("a new indicator moves the panel to match it, and hiding takes the panel off the screen")
    func panelFollowsTheIndicator() async {
        let sut = makeController()

        sut.display(OverlayIndicator.indicator(for: .error(.microphoneNotGranted)))
        await letAppKitLayOut()
        let tall = sut.panelFrame
        sut.display(OverlayIndicator.indicator(for: .inserted))
        await letAppKitLayOut()
        let short = sut.panelFrame
        let visibleWhileShown = sut.isPanelVisible
        sut.display(nil)

        #expect(short.height < tall.height)  // the error wraps to more lines than "Pasted"
        #expect(short.minY == 80)
        #expect(visibleWhileShown)
        #expect(!sut.isPanelVisible)
    }
}
