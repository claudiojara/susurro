import SwiftUI
import Testing
import UITestSupport

@testable import DesignSystem

/// One picture per atom and appearance, each showing every variant of the atom. The references are recorded on the CI
/// image (`record-snapshots`), never here, and `make test` skips these suites by their name.
@MainActor
@Suite("Atom snapshots")
struct AtomSnapshotTests {
    nonisolated private static let schemes: [ColorScheme] = [.light, .dark]

    @Test("text labels in every type role and color", arguments: schemes)
    func labels(scheme: ColorScheme) {
        assertViewSnapshot(
            of: TextLabel.Gallery(), size: CGSize(width: 360, height: 340), scheme: scheme, named: scheme.name)
    }

    @Test("icons in every type role and color", arguments: schemes)
    func icons(scheme: ColorScheme) {
        assertViewSnapshot(of: Icon.Gallery(), scheme: scheme, named: scheme.name)
    }

    @Test("pills in every tint", arguments: schemes)
    func pills(scheme: ColorScheme) {
        assertViewSnapshot(of: Pill.Gallery(), scheme: scheme, named: scheme.name)
    }

    @Test("status dots in every tint", arguments: schemes)
    func statusDots(scheme: ColorScheme) {
        // A dot is a small part of a picture, so the canvas is small too and a wrong dot cannot hide in the tolerance.
        assertViewSnapshot(
            of: StatusDot.Gallery(), size: CGSize(width: 240, height: 80), scheme: scheme, named: scheme.name)
    }

    @Test("level bars from empty to full, in every tint", arguments: schemes)
    func levelBars(scheme: ColorScheme) {
        assertViewSnapshot(of: LevelBar.Gallery(), scheme: scheme, named: scheme.name)
    }

    @Test("buttons of every kind, at rest, pressed, and disabled", arguments: schemes)
    func buttons(scheme: ColorScheme) {
        assertViewSnapshot(of: ActionButton.Gallery(), scheme: scheme, named: scheme.name)
    }
}

extension ColorScheme {
    fileprivate var name: String { self == .dark ? "dark" : "light" }
}
