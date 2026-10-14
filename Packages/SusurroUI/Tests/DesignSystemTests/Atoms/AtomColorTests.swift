import SwiftUI
import Testing
import UITestSupport

@testable import DesignSystem

/// The color of every atom, read from the pixels it paints, in light and dark. A snapshot lets a tenth of a percent of
/// its pixels differ, and a recolored small view can stay under that, so these tests are the ones that say a label,
/// an icon, a dot, a bar, or a button is painted in exactly the color of its token. Text is anti-aliased, so only the
/// pixels inside a stroke have the color of the text: the test looks for a pixel with that color.
@MainActor
@Suite("Atom colors")
struct AtomColorTests {
    /// A channel of a painted pixel is one of 256 values, so it is within half a step of the token.
    private let exact = 1.0 / 255

    nonisolated private static let appearances: [(scheme: ColorScheme, appearance: Appearance)] = [
        (.light, .light), (.dark, .dark),
    ]

    /// No tint is the plain text color.
    nonisolated private static let tints: [Tint?] = [nil] + Tint.allCases.map { Optional($0) }

    private let canvas = CGSize(width: 160, height: 80)

    private func theme(_ appearance: Appearance) throws -> ResolvedTheme {
        try Theme.default.resolved(for: appearance)
    }

    private func image(of view: some View, scheme: ColorScheme, size: CGSize? = nil) -> CGImage {
        SnapshotSupport.cgImage(of: view, size: size ?? canvas, scheme: scheme)
    }

    private func isPainted(_ color: RGBAColor, in image: CGImage, region: CGRect? = nil) -> Bool {
        SnapshotSupport.closestDistance(in: image, to: color, region: region) <= exact
    }

    private func isCenter(_ color: RGBAColor, in image: CGImage) -> Bool {
        let center = SnapshotSupport.pixel(of: image, atX: 0.5, y: 0.5)
        return max(abs(center.red - color.red), abs(center.green - color.green), abs(center.blue - color.blue)) <= exact
    }

    // MARK: Text and icons

    @Test("a label is painted in the color of its tint, or the plain text color", arguments: tints)
    func labelColor(tint: Tint?) throws {
        for (scheme, appearance) in Self.appearances {
            let theme = try theme(appearance)
            let picture = image(of: TextLabel("MMMM", style: .caption, tint: tint), scheme: scheme)
            #expect(isPainted(theme.color(tint.textColor), in: picture), "\(String(describing: tint)) in \(scheme)")
        }
    }

    @Test("a label of every type role is painted in the plain text color", arguments: TypeToken.allCases)
    func labelColorInEveryRole(style: TypeToken) throws {
        for (scheme, appearance) in Self.appearances {
            let picture = image(of: TextLabel("MMMM", style: style), scheme: scheme)
            #expect(isPainted(try theme(appearance).color(.textPrimary), in: picture), "\(style) in \(scheme)")
        }
    }

    @Test("an icon is painted in the color of its tint, or the plain text color", arguments: tints)
    func iconColor(tint: Tint?) throws {
        for (scheme, appearance) in Self.appearances {
            let theme = try theme(appearance)
            let picture = image(of: Icon("circle.fill", style: .title, tint: tint), scheme: scheme)
            #expect(isCenter(theme.color(tint.textColor), in: picture), "\(String(describing: tint)) in \(scheme)")
        }
    }

    // MARK: Pills, dots, and bars

    @Test(
        "a pill has the raised surface for its background and the color of its tint for its text",
        arguments: Tint.allCases)
    func pillColors(tint: Tint) throws {
        for (scheme, appearance) in Self.appearances {
            let theme = try theme(appearance)
            let picture = image(of: Pill("Mmmm", tint: tint), scheme: scheme)
            #expect(isPainted(theme.color(tint.color), in: picture), "\(tint) text in \(scheme)")
            #expect(isPainted(theme.color(.surfaceRaised), in: picture), "\(tint) background in \(scheme)")
        }
    }

    @Test("a status dot is painted in the color of its tint, in light and dark", arguments: Tint.allCases)
    func dotColor(tint: Tint) throws {
        for (scheme, appearance) in Self.appearances {
            let picture = image(of: StatusDot(tint), scheme: scheme, size: CGSize(width: 40, height: 40))
            #expect(isCenter(try theme(appearance).color(tint.color), in: picture), "\(tint) in \(scheme)")
        }
    }

    @Test("a level bar is filled in its tint on the left and is the track color on the right", arguments: Tint.allCases)
    func barColors(tint: Tint) throws {
        let size = CGSize(width: 200, height: 40)
        for (scheme, appearance) in Self.appearances {
            let theme = try theme(appearance)
            let picture = image(of: LevelBar(level: 0.25, tint: tint, label: "Level"), scheme: scheme, size: size)
            let track = theme.color(.surfaceTrack).composited(over: theme.color(.surfaceWindow))
            let filled = SnapshotSupport.pixel(of: picture, atX: 0.2, y: 0.5)
            let empty = SnapshotSupport.pixel(of: picture, atX: 0.6, y: 0.5)
            #expect(distance(filled, theme.color(tint.color)) <= exact, "\(tint) fill in \(scheme): \(filled)")
            #expect(distance(empty, track) <= exact, "\(tint) track in \(scheme): \(empty)")
        }
    }

    @Test("a level bar fills more of its width as the level grows")
    func barFillsFromTheLeft() throws {
        let theme = try theme(.light)
        let size = CGSize(width: 200, height: 40)
        let low = image(of: LevelBar(level: 0.25, tint: .success, label: "Level"), scheme: .light, size: size)
        let high = image(of: LevelBar(level: 0.75, tint: .success, label: "Level"), scheme: .light, size: size)
        let success = theme.color(.statusSuccess)
        let middle = (
            low: SnapshotSupport.pixel(of: low, atX: 0.5, y: 0.5),
            high: SnapshotSupport.pixel(of: high, atX: 0.5, y: 0.5)
        )
        #expect(distance(middle.low, success) > 0.05)
        #expect(distance(middle.high, success) <= exact)
    }

    private func distance(_ first: RGBAColor, _ second: RGBAColor) -> Double {
        max(abs(first.red - second.red), abs(first.green - second.green), abs(first.blue - second.blue))
    }

    // MARK: Buttons

    private enum State: CaseIterable, Sendable { case rest, pressed, disabled }

    /// The fill of a button of `kind` in `state`, as the eye sees it.
    private func fill(of kind: ActionButton.Kind, _ state: State, in theme: ResolvedTheme) -> RGBAColor {
        let rest: ColorToken
        switch kind {
        case .primary: rest = .accentPrimary
        case .secondary: rest = .surfaceRaised
        case .destructive: rest = .statusError
        }
        switch state {
        case .rest: return theme.color(rest)
        case .pressed: return theme.color(.statePressed).composited(over: theme.color(rest))
        case .disabled: return theme.color(.surfaceRaised)
        }
    }

    /// Where the title of the button of `ActionButton("MMMM")` is on the canvas, in points: the middle, without the
    /// padding of the button or its border.
    private static let titleArea = CGRect(x: 58, y: 28, width: 44, height: 24)

    /// The color of the title of a button of `kind` in `state`.
    private func titleColor(of kind: ActionButton.Kind, _ state: State) -> ColorToken {
        if state == .disabled { return .textSecondary }
        return kind == .secondary ? .textPrimary : .textOnAccent
    }

    @Test(
        "a button is filled for its kind and state, and its title has the color for it",
        arguments: ActionButton.Kind.allCases)
    func buttonColors(kind: ActionButton.Kind) throws {
        for (scheme, appearance) in Self.appearances {
            let theme = try theme(appearance)
            for state in State.allCases {
                // A title of one space draws nothing, so the middle of the button is its fill.
                let blank = ActionButtonFace(kind: kind, isPressed: state == .pressed) { Text(" ") }
                let face = image(
                    of: state == .disabled ? AnyView(blank.disabled(true)) : AnyView(blank), scheme: scheme)
                let middle = SnapshotSupport.pixel(of: face, atX: 0.5, y: 0.5)
                #expect(
                    distance(middle, fill(of: kind, state, in: theme)) <= exact, "\(kind) \(state) fill in \(scheme)")
                let titled = ActionButton("MMMM", kind: kind) {}
                let button = image(
                    of: state == .disabled ? AnyView(titled.disabled(true)) : AnyView(titled), scheme: scheme)
                if state != .pressed {
                    // Inside the padding of the button: white text on a blue button is not white on a white window.
                    #expect(
                        isPainted(theme.color(titleColor(of: kind, state)), in: button, region: Self.titleArea),
                        "\(kind) \(state) title in \(scheme)")
                }
            }
        }
    }
}
