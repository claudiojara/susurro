import SwiftUI
import Testing
import UITestSupport

@testable import DesignSystem

/// Each atom takes its sizes and its states from tokens of their own. An atom that borrowed the `sm` space for a dot, or
/// `border.subtle` for a track, would change when a theme changed the space or the border and nothing about the dot or
/// the track. Each test changes the token an atom uses and the token it used to borrow, in separate themes, and looks at
/// the pixels.
@MainActor
@Suite("Atom tokens")
struct AtomTokenTests {
    private let magenta = RGBAColor(red: 1, green: 0, blue: 1)

    /// The default theme with one color token pointed at an opaque magenta, in light and dark.
    private func repainted(_ token: ColorToken) -> Theme {
        var theme = Theme.default
        theme.palette["testMagenta"] = PaletteColor(light: magenta, dark: magenta)
        theme.colors[token.rawValue] = "testMagenta"
        return theme
    }

    private func sized(_ token: SizeToken, _ points: Double) -> Theme {
        var theme = Theme.default
        theme.sizes[token.rawValue] = points
        return theme
    }

    private func spaced(_ token: SpacingToken, _ points: Double) -> Theme {
        var theme = Theme.default
        theme.spacing[token.rawValue] = points
        return theme
    }

    private let canvas = CGSize(width: 120, height: 60)

    /// The width and height, in points, of what is drawn in `color`.
    private func extent<V: View>(of view: V, in theme: Theme, color: ColorToken, scheme: ColorScheme = .light) throws
        -> CGSize
    {
        let resolved = try theme.resolved(for: scheme == .dark ? .dark : .light)
        let image = SnapshotSupport.cgImage(of: view, size: canvas, theme: theme, scheme: scheme)
        let found = try #require(
            SnapshotSupport.extent(of: image, matching: resolved.color(color), tolerance: 0.2),
            "nothing is drawn in \(color)")
        return found.size
    }

    // MARK: Sizes

    @Test("a status dot is as wide as its size token, and the sm space does not change it")
    func dotFollowsItsSize() throws {
        let dot = StatusDot(.accent)
        let normal = try extent(of: dot, in: .default, color: .accentPrimary)
        let bigger = try extent(of: dot, in: sized(.statusDot, 20), color: .accentPrimary)
        let spaced = try extent(of: dot, in: spaced(.sm, 30), color: .accentPrimary)
        #expect(abs(normal.width - 8) <= 1 && abs(normal.height - 8) <= 1, "\(normal)")
        #expect(abs(bigger.width - 20) <= 1 && abs(bigger.height - 20) <= 1, "\(bigger)")
        #expect(spaced == normal)
    }

    @Test("a level bar is as thick as its size token, and the xs space does not change it")
    func barFollowsItsSize() throws {
        let bar = LevelBar(level: 1, label: "Level")
        let normal = try extent(of: bar, in: .default, color: .accentPrimary)
        let thicker = try extent(of: bar, in: sized(.levelBar, 12), color: .accentPrimary)
        let spaced = try extent(of: bar, in: spaced(.xs, 30), color: .accentPrimary)
        #expect(abs(normal.height - 4) <= 1, "\(normal)")
        #expect(abs(thicker.height - 12) <= 1, "\(thicker)")
        #expect(spaced == normal)
    }

    // MARK: States

    private func center(of view: some View, in theme: Theme, size: CGSize) -> RGBAColor {
        let image = SnapshotSupport.cgImage(of: view, size: size, theme: theme, scheme: .light)
        return SnapshotSupport.pixel(of: image, atX: 0.5, y: 0.5)
    }

    @Test("the track of a level bar is the surface.track color, and the subtle border does not change it")
    func trackFollowsItsColor() {
        let empty = LevelBar(level: 0, label: "Level")
        let size = CGSize(width: 120, height: 40)
        let painted = center(of: empty, in: repainted(.surfaceTrack), size: size)
        #expect(abs(painted.red - 1) < 0.01 && painted.green < 0.01 && abs(painted.blue - 1) < 0.01, "\(painted)")
        #expect(center(of: empty, in: repainted(.borderSubtle), size: size) == center(of: empty, in: .default, size: size))
    }

    @Test("a pressed button is veiled in the state.pressed color, and the subtle border does not change the veil")
    func pressedFollowsItsColor() {
        let pressed = ActionButtonFace(kind: .primary, isPressed: true) { Text(" ") }
        let size = CGSize(width: 120, height: 60)
        let image = SnapshotSupport.cgImage(of: pressed, size: size, theme: repainted(.statePressed), scheme: .light)
        // The middle of the button, where the text is a space and draws nothing.
        let veil = SnapshotSupport.pixel(of: image, atX: 0.5, y: 0.5)
        #expect(abs(veil.red - 1) < 0.01 && veil.green < 0.01 && abs(veil.blue - 1) < 0.01, "\(veil)")
        let before = SnapshotSupport.cgImage(of: pressed, size: size, theme: .default, scheme: .light)
        let after = SnapshotSupport.cgImage(of: pressed, size: size, theme: repainted(.borderSubtle), scheme: .light)
        #expect(
            SnapshotSupport.pixel(of: before, atX: 0.5, y: 0.5) == SnapshotSupport.pixel(of: after, atX: 0.5, y: 0.5))
    }
}
