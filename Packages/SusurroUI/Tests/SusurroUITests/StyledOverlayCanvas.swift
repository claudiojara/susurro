import SwiftUI
import Testing
import UITestSupport

@testable import SusurroUI

/// The canvas each state of the other overlay styles is drawn on for its snapshot: the same states as `OverlayCanvas`,
/// which is the pill's. The sizes are written here, not measured, for the reason `OverlayCanvas` gives, and
/// `StyledOverlayCanvasTests` checks that each is just big enough.
struct StyledOverlayCanvas: CaseIterable, Sendable, Hashable, CustomTestStringConvertible {
    enum Style: String, CaseIterable, Sendable {
        case minimal, liveText
    }

    let style: Style
    let state: OverlayCanvas

    static let allCases: [StyledOverlayCanvas] = Style.allCases.flatMap { style in
        OverlayCanvas.allCases.map { StyledOverlayCanvas(style: style, state: $0) }
    }

    var testDescription: String { "\(style.rawValue)-\(state)" }

    var size: CGSize {
        switch style {
        case .minimal: CGSize(width: 232, height: minimalHeight)
        case .liveText: CGSize(width: 552, height: liveTextHeight)
        }
    }

    private var minimalHeight: CGFloat {
        switch state {
        case .notice: 96
        case .error: 96
        case .starting, .recordingHold, .recordingHandsFree, .transcribing, .loadingModel, .polishing, .inserted: 66
        }
    }

    private var liveTextHeight: CGFloat {
        switch state {
        case .recordingHold: 150
        case .recordingHandsFree: 168
        case .loadingModel: 96
        case .starting, .transcribing, .polishing, .inserted, .notice, .error: 82
        }
    }

    #if DEBUG
        @MainActor var view: AnyView {
            switch style {
            case .minimal: MinimalOverlayStyle().body(state: state.state, level: OverlayFixtures.level)
            case .liveText:
                LiveTextOverlayStyle().body(
                    state: state.state, level: OverlayFixtures.level, transcript: OverlayFixtures.transcript)
            }
        }
    #endif
}

@MainActor
@Suite("Styled overlay canvases")
struct StyledOverlayCanvasTests {
    /// As in `OverlayCanvasTests`.
    private let slack: CGFloat = 24

    @Test(
        "a canvas holds its view and the margin in light and dark, with little to spare",
        arguments: StyledOverlayCanvas.allCases)
    func canvasFitsItsView(canvas: StyledOverlayCanvas) {
        let margin = SnapshotSupport.margin()
        for scheme in [ColorScheme.light, .dark] {
            let needed =
                Probe.height(of: canvas.view, width: canvas.size.width - 2 * margin, scheme: scheme) + 2 * margin
            #expect(needed > 2 * margin, "\(canvas): the view has no height")
            #expect(canvas.size.height >= needed, "\(canvas) is too short in \(scheme): \(needed) points are needed")
            #expect(
                canvas.size.height - needed <= slack, "\(canvas) is much taller than its view in \(scheme): \(needed)")
        }
    }

    @Test("a state drawn twice gives the same picture", arguments: StyledOverlayCanvas.allCases, Probe.schemes)
    func renderIsStable(canvas: StyledOverlayCanvas, scheme: ColorScheme) {
        let first = SnapshotSupport.pngData(of: canvas.view, size: canvas.size, scheme: scheme)
        let second = SnapshotSupport.pngData(of: canvas.view, size: canvas.size, scheme: scheme)

        #expect(first == second)
    }
}
