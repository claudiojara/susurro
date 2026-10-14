import Testing

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

    @Test("each tint is the color role it stands for, and every tint is in the table", arguments: tints)
    func tintMapsToItsRole(tint: Tint, color: ColorToken) {
        #expect(tint.color == color)
        #expect(Set(Self.tints.map(\.color)).count == Tint.allCases.count, "two tints stand for one role")
        #expect(Tint.allCases.count == Self.tints.count)
    }

    @Test("text and icons without a tint use the plain text color, and with one use the color of the tint")
    func plainTextHasNoTint() {
        let plain: Tint? = nil
        #expect(plain.textColor == .textPrimary)
        for (tint, color) in Self.tints {
            let tinted: Tint? = tint
            #expect(tinted.textColor == color)
        }
    }
}
