import SwiftUI
import Testing
import UITestSupport

@testable import DesignSystem
@testable import SusurroUI

@MainActor
@Suite("Overlay rendering")
struct OverlayRenderingTests {
    @Test("a state drawn twice gives the same picture", arguments: OverlayCanvas.allCases, Probe.schemes)
    func renderIsStable(canvas: OverlayCanvas, scheme: ColorScheme) {
        let first = SnapshotSupport.pngData(of: canvas.view, size: canvas.size, scheme: scheme)
        let second = SnapshotSupport.pngData(of: canvas.view, size: canvas.size, scheme: scheme)

        #expect(first == second)
    }

    @Test("every state is drawn differently from every other", arguments: Probe.schemes)
    func statesDiffer(scheme: ColorScheme) {
        let pictures = OverlayCanvas.allCases.map {
            SnapshotSupport.pngData(of: $0.view, size: CGSize(width: 412, height: 160), scheme: scheme)
        }

        #expect(Set(pictures).count == pictures.count)
    }

    @Test("the input level moves the meter while recording, and only then")
    func levelDrawsTheMeter() {
        let size = OverlayCanvas.recordingHold.size
        func picture(_ state: OverlayViewState, level: Double) -> Data {
            SnapshotSupport.pngData(of: OverlayHUD(state: state, level: level), size: size, scheme: .light)
        }
        let recording = OverlayCanvas.recordingHold.state
        let transcribing = OverlayCanvas.transcribing.state

        #expect(picture(recording, level: 0.1) != picture(recording, level: 0.9))
        #expect(picture(transcribing, level: 0.1) == picture(transcribing, level: 0.9))
    }

    @Test("each state paints the color role of its symbol")
    func tintsComeFromTheTheme() throws {
        let light = try Probe.theme(.light)
        let recording = Probe.picture(
            of: OverlayHUD(state: OverlayCanvas.recordingHold.state, level: 0.9),
            size: OverlayCanvas.recordingHold.size, scheme: .light)
        let error = Probe.picture(
            of: OverlayHUD(state: OverlayCanvas.error.state), size: OverlayCanvas.error.size, scheme: .light)

        let inserted = Probe.picture(
            of: OverlayHUD(state: OverlayCanvas.inserted.state), size: OverlayCanvas.inserted.size, scheme: .light)

        #expect(Probe.isPainted(light.color(.accentRecording), in: recording))
        #expect(Probe.isPainted(light.color(.statusError), in: error))
        #expect(Probe.isPainted(light.color(.statusSuccess), in: inserted))
        #expect(!Probe.isPainted(light.color(.statusSuccess), in: error))
    }

    @Test("the overlay is as wide as the theme says")
    func widthComesFromTheTheme() {
        var theme = Theme.default
        let hud = OverlayHUD(state: OverlayCanvas.inserted.state)
        let standard = SnapshotSupport.idealSize(of: hud, theme: theme, scheme: .light)
        theme.overlay.width = 300
        let narrow = SnapshotSupport.idealSize(of: hud, theme: theme, scheme: .light)

        #expect(standard.width == CGFloat(Theme.default.overlay.width))
        #expect(narrow.width == 300)
    }

    @Test("a hands-free recording is taller than a hold, since it carries the hint")
    func handsFreeHasAHint() {
        let hold = SnapshotSupport.idealSize(
            of: OverlayHUD(state: OverlayCanvas.recordingHold.state), scheme: .light)
        let handsFree = SnapshotSupport.idealSize(
            of: OverlayHUD(state: OverlayCanvas.recordingHandsFree.state), scheme: .light)

        #expect(handsFree.height > hold.height)
    }

    @Test("a hidden state draws nothing")
    func hiddenDrawsNothing() {
        let size = OverlayCanvas.inserted.size

        #expect(
            SnapshotSupport.pngData(of: OverlayHUD(state: .hidden), size: size, scheme: .light)
                == SnapshotSupport.pngData(of: Color.clear, size: size, scheme: .light))
    }
}

@MainActor
@Suite("Overlay canvases")
struct OverlayCanvasTests {
    /// The most a canvas may exceed its view and the margin by, in points: room for the fonts of another macOS to measure
    /// a little differently, and no more.
    private let slack: CGFloat = 24

    @Test(
        "a canvas holds its view and the margin in light and dark, with little to spare",
        arguments: OverlayCanvas.allCases)
    func canvasFitsItsView(canvas: OverlayCanvas) {
        let margin = SnapshotSupport.margin()
        for scheme in [ColorScheme.light, .dark] {
            let needed =
                Probe.height(of: canvas.view, width: canvas.size.width - 2 * margin, scheme: scheme) + 2 * margin
            #expect(needed > 2 * margin, "\(canvas): the view has no height")
            #expect(canvas.size.height >= needed, "\(canvas) is too short in \(scheme): \(needed) points are needed")
            #expect(canvas.size.height - needed <= slack, "\(canvas) is much taller than its view in \(scheme)")
        }
    }
}
