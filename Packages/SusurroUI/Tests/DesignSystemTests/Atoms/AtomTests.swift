import SwiftUI
import Testing
import UITestSupport

@testable import DesignSystem

@MainActor
@Suite("Atoms")
struct AtomTests {
    nonisolated private static let levels: [(given: Double, shown: Double)] = [
        (0, 0), (0.25, 0.25), (1, 1), (-0.5, 0), (1.7, 1), (.nan, 0), (.infinity, 0), (-.infinity, 0),
    ]

    @Test(
        "a level bar shows the level from empty to full, and an empty bar for a number it cannot show",
        arguments: levels)
    func levelBarClampsTheLevel(given: Double, shown: Double) {
        #expect(LevelBar.shown(level: given) == shown)
    }

    nonisolated private static let tints: [(tint: Tint, color: ColorToken)] = [
        (.neutral, .textSecondary), (.accent, .accentPrimary), (.recording, .accentRecording),
        (.success, .statusSuccess), (.warning, .statusWarning), (.error, .statusError),
    ]

    @Test("a status dot is painted in the color of its tint, in light and dark", arguments: tints)
    func dotColor(tint: Tint, color: ColorToken) throws {
        #expect(Tint.allCases.count == Self.tints.count)
        for (scheme, appearance) in [(ColorScheme.light, Appearance.light), (.dark, .dark)] {
            let theme = try Theme.default.resolved(for: appearance)
            let image = SnapshotSupport.cgImage(
                of: StatusDot(tint), size: CGSize(width: 40, height: 40), theme: .default, scheme: scheme)
            let center = SnapshotSupport.pixel(of: image, atX: 0.5, y: 0.5)
            let expected = theme.color(color)
            #expect(abs(center.red - expected.red) < 0.01, "\(tint) red in \(scheme)")
            #expect(abs(center.green - expected.green) < 0.01, "\(tint) green in \(scheme)")
            #expect(abs(center.blue - expected.blue) < 0.01, "\(tint) blue in \(scheme)")
        }
    }

    @Test("a level bar fills the left part of its width and leaves the rest as the track")
    func levelBarFillsFromTheLeft() throws {
        let theme = try Theme.default.resolved(for: .light)
        let image = SnapshotSupport.cgImage(
            of: LevelBar("Level", level: 0.5, tint: .success), size: CGSize(width: 200, height: 40), theme: .default,
            scheme: .light)
        let filled = SnapshotSupport.pixel(of: image, atX: 0.3, y: 0.5)
        let empty = SnapshotSupport.pixel(of: image, atX: 0.9, y: 0.5)
        #expect(abs(filled.green - theme.color(.statusSuccess).green) < 0.01)
        #expect(abs(filled.red - theme.color(.statusSuccess).red) < 0.01)
        #expect(abs(empty.green - theme.color(.statusSuccess).green) > 0.05)
    }
}
