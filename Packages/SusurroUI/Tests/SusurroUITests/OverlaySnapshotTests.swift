import SwiftUI
import Testing
import UITestSupport

@testable import DesignSystem
@testable import SusurroUI

/// One picture per overlay state and appearance, with the default theme and the motion off. The references are recorded
/// on the CI image (`record-snapshots`), never here, and `make test` skips these suites by their name.
@MainActor
@Suite("Overlay snapshots")
struct OverlaySnapshotTests {
    @Test("every state of the overlay, in light and dark", arguments: OverlayCanvas.allCases, Probe.schemes)
    func states(canvas: OverlayCanvas, scheme: ColorScheme) {
        assertViewSnapshot(of: canvas.view, size: canvas.size, scheme: scheme, named: "\(canvas)-\(scheme.pictureName)")
    }
}
