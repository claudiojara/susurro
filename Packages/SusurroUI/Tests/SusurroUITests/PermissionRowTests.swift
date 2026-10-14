import SwiftUI
import Testing
import UITestSupport

@testable import DesignSystem
@testable import SusurroUI

/// What a permission row paints, read from its pixels and its size, in light and dark. The snapshots say the picture did
/// not change; these say what is in it.
@MainActor
@Suite("Permission row")
struct PermissionRowTests {
    private let width: CGFloat = 424
    private var canvas: CGSize { CGSize(width: width, height: 260) }

    private func row(_ fixture: OnboardingFixtures.Row, onAction: @escaping (OnboardingAction) -> Void = { _ in })
        -> PermissionRow
    {
        PermissionRow(OnboardingFixtures.row(fixture), onAction: onAction)
    }

    /// The row's contents have this much room on each side of the card.
    private var cardWidth: CGFloat { width - 2 * SnapshotSupport.margin() }

    // MARK: Colors

    @Test(
        "the icon and the pill are painted in the tint of the status",
        arguments: [
            (OnboardingFixtures.Row.granted, ColorToken.statusSuccess),
            (.denied, .statusError),
            (.waitingForPrompt, .statusPending),
            (.waitingInSettings, .statusPending),
            (.stale, .statusWarning),
        ])
    func statusTint(fixture: OnboardingFixtures.Row, token: ColorToken) throws {
        for scheme in Probe.schemes {
            let picture = Probe.picture(of: row(fixture), size: canvas, scheme: scheme)

            let painted = try #require(
                SnapshotSupport.extent(of: picture, matching: Probe.theme(scheme).color(token), tolerance: Probe.exact),
                "\(fixture) paints nothing in \(token) in \(scheme)")

            // The icon is at the left end of the first line and the pill at the right end, and both take the tint.
            #expect(painted.minX < 60 && painted.maxX > 300, "\(fixture) in \(scheme): \(painted)")
        }
    }

    @Test("the troubleshooting steps of a stale row are painted in the warning color, below the first line")
    func guidanceTint() throws {
        for scheme in Probe.schemes {
            let theme = try Probe.theme(scheme)
            let stale = Probe.picture(of: row(.stale), size: canvas, scheme: scheme)
            let waiting = Probe.picture(of: row(.waitingInSettings), size: canvas, scheme: scheme)

            let steps = try #require(
                SnapshotSupport.extent(of: stale, matching: theme.color(.statusWarning), tolerance: Probe.exact))
            let status = try #require(
                SnapshotSupport.extent(of: waiting, matching: theme.color(.statusPending), tolerance: Probe.exact))

            // The first line holds the icon and the pill and is about as tall as the icon; the steps are lines below it.
            #expect(steps.height > status.height + 30, "\(steps) against \(status) in \(scheme)")
        }
    }

    @Test("the row is a raised card on the window", arguments: Probe.schemes)
    func cardIsRaised(scheme: ColorScheme) throws {
        let theme = try Probe.theme(scheme)
        let picture = Probe.picture(of: row(.granted), size: canvas, scheme: scheme)

        let card = try #require(
            SnapshotSupport.extent(of: picture, matching: theme.color(.surfaceRaised), tolerance: Probe.exact))

        // The border takes a point on each side.
        #expect(abs(card.width - cardWidth) <= 3, "\(card)")
    }

    @Test(
        "a request is a button filled in the accent, and opening System Settings is not",
        arguments: [
            (OnboardingFixtures.Row.notAsked, true),
            (.optional, true),
            (.denied, false),
            (.stale, false),
        ])
    func buttonFill(fixture: OnboardingFixtures.Row, filled: Bool) throws {
        for scheme in Probe.schemes {
            let theme = try Probe.theme(scheme)
            let picture = Probe.picture(of: row(fixture), size: canvas, scheme: scheme)

            // The accent is only the fill of a button here: the paint of a button is at least as wide as its title.
            let found = SnapshotSupport.extent(
                of: picture, matching: theme.color(.accentPrimary), tolerance: Probe.exact)
            let isButton = (found?.width ?? 0) > 40
            #expect(isButton == filled, "\(fixture) in \(scheme): \(String(describing: found))")
        }
    }

    // MARK: Parts

    @Test("a row with an action is taller than the same row without one")
    func actionAddsAButton() {
        let withAction = Probe.height(of: row(.waitingInSettings), width: cardWidth)
        let without = Probe.height(of: row(.waitingForPrompt), width: cardWidth)

        #expect(withAction > without + 20, "\(withAction) against \(without)")
    }

    @Test("the reason why the permission is needed is drawn, and wraps when it is long")
    func whyIsDrawn() {
        let short = OnboardingFixtures.row(.granted)
        let long = short.with(why: String(repeating: "Needed to hear you. ", count: 12))

        let shortHeight = Probe.height(of: PermissionRow(short) { _ in }, width: cardWidth)
        let longHeight = Probe.height(of: PermissionRow(long) { _ in }, width: cardWidth)

        #expect(longHeight > shortHeight + 40, "\(longHeight) against \(shortHeight)")
    }

    @Test("the feature note of an optional permission is drawn")
    func featureNoteIsDrawn() {
        let optional = OnboardingFixtures.row(.optional)
        let required = optional.with(requirement: .required)

        let withNote = Probe.height(of: PermissionRow(optional) { _ in }, width: cardWidth)
        let without = Probe.height(of: PermissionRow(required) { _ in }, width: cardWidth)

        #expect(withNote > without + 10, "\(withNote) against \(without)")
    }

    @Test("the troubleshooting steps of a stale row are drawn, and a longer text is taller")
    func guidanceIsDrawn() {
        let stale = OnboardingFixtures.row(.stale)
        let shortened = stale.with(status: .stale(guidance: "Switch it off and on."))
        let waiting = stale.with(status: .waiting)

        let long = Probe.height(of: PermissionRow(stale) { _ in }, width: cardWidth)
        let short = Probe.height(of: PermissionRow(shortened) { _ in }, width: cardWidth)
        let none = Probe.height(of: PermissionRow(waiting) { _ in }, width: cardWidth)

        #expect(none < short)
        #expect(short < long)
    }

    // MARK: Words

    @Test("the row draws the status text of its state in the pill, and the title and the action as they are given")
    func wordsComeFromTheRow() {
        let base = OnboardingFixtures.row(.notAsked)
        let variants: [OnboardingRowState] = [
            base.with(statusText: "Still to do"), base.with(title: "Mic"),
            base.with(action: .some(OnboardingAction(kind: .request, title: "Turn it on"))),
        ]

        let before = Probe.picture(of: row(.notAsked), size: canvas, scheme: .light)
        let same = Probe.picture(of: PermissionRow(base) { _ in }, size: canvas, scheme: .light)

        #expect(SnapshotSupport.differingPixels(before, same, tolerance: 0.02) == 0)
        for variant in variants {
            let after = Probe.picture(of: PermissionRow(variant) { _ in }, size: canvas, scheme: .light)
            #expect(SnapshotSupport.differingPixels(before, after, tolerance: 0.02) > 40, "\(variant)")
        }
    }

    // MARK: Look

    @Test("a theme with another pending color repaints the waiting status and nothing of a granted row")
    func followsTheTheme() throws {
        let other = Self.themeWith(ColorToken.statusPending)

        let waitingNow = Probe.picture(of: row(.waitingForPrompt), size: canvas, scheme: .light)
        let waitingThen = Probe.picture(of: row(.waitingForPrompt), size: canvas, scheme: .light, theme: other)
        let grantedNow = Probe.picture(of: row(.granted), size: canvas, scheme: .light)
        let grantedThen = Probe.picture(of: row(.granted), size: canvas, scheme: .light, theme: other)

        #expect(SnapshotSupport.differingPixels(waitingNow, waitingThen, tolerance: 0.02) > 50)
        #expect(SnapshotSupport.differingPixels(grantedNow, grantedThen, tolerance: 0.02) == 0)
    }

    @Test("a theme with another accent leaves a waiting row as it was: waiting is not the accent")
    func accentDoesNotPaintWaiting() {
        let other = Self.themeWith(ColorToken.accentPrimary)

        let now = Probe.picture(of: row(.waitingForPrompt), size: canvas, scheme: .light)
        let then = Probe.picture(of: row(.waitingForPrompt), size: canvas, scheme: .light, theme: other)

        #expect(SnapshotSupport.differingPixels(now, then, tolerance: 0.02) == 0)
    }

    /// The default theme with one color token pointed at magenta.
    private static func themeWith(_ token: ColorToken) -> Theme {
        var other = Theme.default
        other.palette["testMagenta"] = PaletteColor(
            light: .init(red: 1, green: 0, blue: 1), dark: .init(red: 1, green: 0, blue: 1))
        other.colors[token.rawValue] = "testMagenta"
        return other
    }
}
