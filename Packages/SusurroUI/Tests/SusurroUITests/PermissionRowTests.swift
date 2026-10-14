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
        "the status is painted in the tint of the status",
        arguments: [
            (OnboardingFixtures.Row.granted, ColorToken.statusSuccess),
            (.denied, .statusError),
            (.waitingForPrompt, .accentPrimary),
            (.waitingInSettings, .accentPrimary),
            (.stale, .statusWarning),
        ], Probe.schemes)
    func statusTint(fixture: OnboardingFixtures.Row, token: ColorToken, scheme: ColorScheme) throws {
        let picture = Probe.picture(of: row(fixture), size: canvas, scheme: scheme)

        #expect(Probe.isPainted(try Probe.theme(scheme).color(token), in: picture), "\(fixture) in \(scheme)")
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
        ], Probe.schemes)
    func buttonFill(fixture: OnboardingFixtures.Row, filled: Bool, scheme: ColorScheme) throws {
        let theme = try Probe.theme(scheme)
        let picture = Probe.picture(of: row(fixture), size: canvas, scheme: scheme)

        // The accent also colors the icon and the pill of a waiting row, so only rows whose status is not in the accent
        // are looked at: the paint of a button is at least as wide as its title, and an icon is a few points wide.
        let found = SnapshotSupport.extent(of: picture, matching: theme.color(.accentPrimary), tolerance: Probe.exact)
        #expect((found?.width ?? 0) > 40 == filled, "\(fixture) in \(scheme): \(String(describing: found))")
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
        let long = OnboardingRowState(
            id: short.id, title: short.title, why: String(repeating: "Needed to hear you. ", count: 12),
            requirement: short.requirement, status: short.status, action: short.action)

        let shortHeight = Probe.height(of: PermissionRow(short) { _ in }, width: cardWidth)
        let longHeight = Probe.height(of: PermissionRow(long) { _ in }, width: cardWidth)

        #expect(longHeight > shortHeight + 40, "\(longHeight) against \(shortHeight)")
    }

    @Test("the feature note of an optional permission is drawn")
    func featureNoteIsDrawn() {
        let optional = OnboardingFixtures.row(.optional)
        let required = OnboardingRowState(
            id: optional.id, title: optional.title, why: optional.why, requirement: .required,
            status: optional.status, action: optional.action)

        let withNote = Probe.height(of: PermissionRow(optional) { _ in }, width: cardWidth)
        let without = Probe.height(of: PermissionRow(required) { _ in }, width: cardWidth)

        #expect(withNote > without + 10, "\(withNote) against \(without)")
    }

    @Test("the troubleshooting steps of a stale row are drawn, and a longer text is taller")
    func guidanceIsDrawn() {
        let stale = OnboardingFixtures.row(.stale)
        let shortened = OnboardingRowState(
            id: stale.id, title: stale.title, why: stale.why, requirement: stale.requirement,
            status: .stale(guidance: "Switch it off and on."), action: stale.action)
        let waiting = OnboardingRowState(
            id: stale.id, title: stale.title, why: stale.why, requirement: stale.requirement, status: .waiting,
            action: stale.action)

        let long = Probe.height(of: PermissionRow(stale) { _ in }, width: cardWidth)
        let short = Probe.height(of: PermissionRow(shortened) { _ in }, width: cardWidth)
        let none = Probe.height(of: PermissionRow(waiting) { _ in }, width: cardWidth)

        #expect(none < short)
        #expect(short < long)
    }

    // MARK: Look

    @Test("a theme with another accent repaints the waiting status and nothing of a granted row")
    func followsTheTheme() throws {
        var other = Theme.default
        other.palette["testMagenta"] = PaletteColor(
            light: .init(red: 1, green: 0, blue: 1), dark: .init(red: 1, green: 0, blue: 1))
        other.colors[ColorToken.accentPrimary.rawValue] = "testMagenta"

        let waitingNow = Probe.picture(of: row(.waitingForPrompt), size: canvas, scheme: .light)
        let waitingThen = Probe.picture(of: row(.waitingForPrompt), size: canvas, scheme: .light, theme: other)
        let grantedNow = Probe.picture(of: row(.granted), size: canvas, scheme: .light)
        let grantedThen = Probe.picture(of: row(.granted), size: canvas, scheme: .light, theme: other)

        #expect(SnapshotSupport.differingPixels(waitingNow, waitingThen, tolerance: 0.02) > 50)
        #expect(SnapshotSupport.differingPixels(grantedNow, grantedThen, tolerance: 0.02) == 0)
    }
}
