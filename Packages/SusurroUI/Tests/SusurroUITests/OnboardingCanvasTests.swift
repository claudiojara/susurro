import SwiftUI
import Testing
import UITestSupport

@testable import SusurroUI

/// A picture matches when 99.9 % of its pixels do, so a view that is a small part of its canvas can change without a
/// snapshot test noticing. Each view is drawn on a canvas just big enough for it, and these tests keep the sizes written
/// in `OnboardingCanvas` from drifting away from the views. The colors are checked on the pixels, in the tests of each
/// view.
@MainActor
@Suite("Onboarding canvases")
struct OnboardingCanvasTests {
    /// The most a canvas may exceed its view and the margin by, in points: room for the fonts of another macOS to measure
    /// a little differently, and no more.
    private let slack: CGFloat = 24

    @Test(
        "a canvas holds its view and the margin in light and dark, with little to spare",
        arguments: OnboardingCanvas.allCases)
    func canvasFitsItsView(canvas: OnboardingCanvas) {
        let margin = SnapshotSupport.margin()
        for scheme in [ColorScheme.light, .dark] {
            // A view that fills its width wraps its text to the width of the canvas, so the height is measured there.
            let needed =
                Probe.height(of: canvas.view, width: canvas.size.width - 2 * margin, scheme: scheme) + 2 * margin
            #expect(needed > 2 * margin, "\(canvas): the view has no height")
            #expect(canvas.size.height >= needed, "\(canvas) is too short in \(scheme): \(needed) points are needed")
            #expect(canvas.size.height - needed <= slack, "\(canvas) is much taller than its view in \(scheme)")
        }
    }
}
