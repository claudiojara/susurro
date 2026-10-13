import SwiftUI
import Testing
import UITestSupport

@testable import DesignSystem

/// A picture matches when 99.9 % of its pixels do, so a view that is a small part of its canvas can change without a
/// snapshot test noticing: a canvas of 100,000 pixels lets 100 of them differ, and a caption-sized icon that is recolored
/// changes about 200. So each gallery is drawn on a canvas just big enough for it, and the smallest view of each is checked
/// to change clearly more pixels than its canvas lets pass. The sizes are in `AtomCanvas`; these tests keep them from
/// drifting away from the galleries.
@MainActor
@Suite("Atom canvases")
struct AtomCanvasTests {
    /// The most a canvas may exceed its gallery and the margin by, in points on each side: room for the fonts of another
    /// macOS to measure a little differently, and no more.
    private let slack: CGFloat = 24

    @Test(
        "a canvas holds its gallery and the margin in light and dark, with little to spare",
        arguments: AtomCanvas.allCases)
    func canvasFitsItsGallery(canvas: AtomCanvas) {
        let margin = SnapshotSupport.margin()
        for scheme in [ColorScheme.light, .dark] {
            let content = canvas.contentSize(scheme: scheme)
            #expect(content.height > 0, "\(canvas): the gallery has no height")
            let needed = CGSize(width: content.width + 2 * margin, height: content.height + 2 * margin)
            #expect(canvas.size.height >= needed.height, "\(canvas) is too short for its gallery in \(scheme)")
            #expect(canvas.size.height - needed.height <= slack, "\(canvas) is much taller than its gallery")
            if canvas.fillsItsWidth {
                // A bar takes the width it is offered, so the canvas decides it; the gallery only has to fit.
                #expect(canvas.size.width >= needed.width, "\(canvas) is too narrow in \(scheme)")
            } else {
                #expect(canvas.size.width >= needed.width, "\(canvas) is too narrow for its gallery in \(scheme)")
                #expect(canvas.size.width - needed.width <= slack, "\(canvas) is much wider than its gallery")
            }
        }
    }

    @Test(
        "recoloring the smallest view of a gallery changes half as many pixels again as its canvas lets differ",
        arguments: AtomCanvas.allCases)
    func theSmallestChangeIsSeen(canvas: AtomCanvas) {
        let pixels = canvas.size.width * canvas.size.height * SnapshotSupport.scale * SnapshotSupport.scale
        let hidden = Double(pixels) * Double(1 - SnapshotSupport.precision)
        for scheme in [ColorScheme.light, .dark] {
            let changed = Double(canvas.recoloredPixels(scheme: scheme))
            #expect(
                changed >= 1.5 * hidden,
                "\(canvas): \(Int(changed)) pixels change, \(Int(hidden)) may go unseen in \(scheme)")
        }
    }
}
