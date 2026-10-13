import SwiftUI
import Testing
import UITestSupport

@testable import DesignSystem

/// One picture per atom and appearance, each showing every variant of the atom on a canvas just big enough for it
/// (`AtomCanvas`). The references are recorded on the CI image (`record-snapshots`), never here, and `make test` skips
/// these suites by their name.
@MainActor
@Suite("Atom snapshots")
struct AtomSnapshotTests {
    nonisolated private static let schemes: [ColorScheme] = [.light, .dark]

    @Test("text labels in every type role and color", arguments: schemes)
    func labels(scheme: ColorScheme) {
        assertViewSnapshot(of: TextLabel.Gallery(), size: AtomCanvas.labels.size, scheme: scheme, named: scheme.name)
    }

    @Test("icons in every type role and color", arguments: schemes)
    func icons(scheme: ColorScheme) {
        assertViewSnapshot(of: Icon.Gallery(), size: AtomCanvas.icons.size, scheme: scheme, named: scheme.name)
    }

    @Test("pills in every tint", arguments: schemes)
    func pills(scheme: ColorScheme) {
        assertViewSnapshot(of: Pill.Gallery(), size: AtomCanvas.pills.size, scheme: scheme, named: scheme.name)
    }

    @Test("status dots in every tint", arguments: schemes)
    func statusDots(scheme: ColorScheme) {
        assertViewSnapshot(
            of: StatusDot.Gallery(), size: AtomCanvas.statusDots.size, scheme: scheme, named: scheme.name)
    }

    @Test("level bars from empty to full, in every tint", arguments: schemes)
    func levelBars(scheme: ColorScheme) {
        assertViewSnapshot(of: LevelBar.Gallery(), size: AtomCanvas.levelBars.size, scheme: scheme, named: scheme.name)
    }

    @Test("buttons of every kind, at rest, pressed, and disabled", arguments: schemes)
    func buttons(scheme: ColorScheme) {
        assertViewSnapshot(
            of: ActionButton.Gallery(), size: AtomCanvas.buttons.size, scheme: scheme, named: scheme.name)
    }
}

extension ColorScheme {
    fileprivate var name: String { self == .dark ? "dark" : "light" }
}
