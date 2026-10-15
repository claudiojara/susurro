import SwiftUI
import Testing
import UITestSupport

@testable import DesignSystem
@testable import SusurroUI

/// One picture per state and appearance of the minimal pill and of the live text panel, with the default theme and the
/// motion off. The pill has its own suite (`OverlaySnapshotTests`). The references are recorded on the CI image
/// (`record-snapshots`), never here, and `make test` skips these suites by their name.
@MainActor
@Suite("Styled overlay snapshots")
struct StyledOverlaySnapshotTests {
    @Test(
        "every state of the minimal pill and the live text, in light and dark",
        arguments: StyledOverlayCanvas.allCases, Probe.schemes)
    func states(canvas: StyledOverlayCanvas, scheme: ColorScheme) {
        assertViewSnapshot(
            of: canvas.view, size: canvas.size, scheme: scheme, named: "\(canvas.testDescription)-\(scheme.pictureName)"
        )
    }
}
