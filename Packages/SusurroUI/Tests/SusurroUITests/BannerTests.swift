import SwiftUI
import Testing
import UITestSupport

@testable import DesignSystem
@testable import SusurroUI

/// What the warning banner paints and how it lays out, read from its pixels and its size, in light and dark.
@MainActor
@Suite("Banner")
struct BannerTests {
    private let width: CGFloat = 424
    private var canvas: CGSize { CGSize(width: width, height: 120) }
    private var contentWidth: CGFloat { width - 2 * SnapshotSupport.margin() }

    @Test("the icon and the message are painted in the warning color, the icon at the left and the message after it")
    func warningTint() throws {
        for scheme in Probe.schemes {
            let theme = try Probe.theme(scheme)
            let picture = Probe.picture(of: Banner("Dictation is off."), size: canvas, scheme: scheme)

            let painted = try #require(
                SnapshotSupport.extent(of: picture, matching: theme.color(.statusWarning), tolerance: Probe.exact))

            #expect(painted.minX < 60, "the icon is at the left: \(painted) in \(scheme)")
            #expect(painted.width > 100, "the message is painted too: \(painted) in \(scheme)")
        }
    }

    @Test("the banner is a raised card on the window", arguments: Probe.schemes)
    func cardIsRaised(scheme: ColorScheme) throws {
        let theme = try Probe.theme(scheme)
        let picture = Probe.picture(of: Banner("Dictation is off."), size: canvas, scheme: scheme)

        let card = try #require(
            SnapshotSupport.extent(of: picture, matching: theme.color(.surfaceRaised), tolerance: Probe.exact))

        #expect(abs(card.width - contentWidth) <= 3, "\(card)")
    }

    @Test("a long message wraps and makes the banner taller, and a short one stays on one line")
    func messageWraps() {
        let short = Probe.height(of: Banner("Dictation is off."), width: contentWidth)
        let long = Probe.height(of: Banner(String(repeating: "Dictation is off. ", count: 12)), width: contentWidth)

        #expect(long > short + 30, "\(long) against \(short)")
    }

    @Test("the space around the message and between it and the icon come from the theme")
    func spacingFollowsTheTheme() {
        let banner = Banner("Dictation is off.")

        let normal = Probe.height(of: banner, width: contentWidth)
        let roomy = Probe.height(of: banner, width: contentWidth, theme: Probe.spaced(.md, 30))

        // The padding of the card is spacing.md on each side.
        #expect(abs((roomy - normal) - 2 * (30 - 12)) <= 1, "\(roomy) against \(normal)")
    }

    @Test("the gap between the icon and the message is the sm space")
    func gapFollowsTheTheme() throws {
        let banner = Banner("Dictation is off.")
        func painted(_ theme: Theme) throws -> CGRect {
            let picture = Probe.picture(of: banner, size: canvas, scheme: .light, theme: theme)
            let warning = try Probe.theme(.light, of: theme).color(.statusWarning)
            return try #require(SnapshotSupport.extent(of: picture, matching: warning, tolerance: Probe.exact))
        }

        let widened = try painted(Probe.spaced(.sm, 30)).width - painted(.default).width

        #expect(abs(widened - (30 - 8)) <= 2, "\(widened)")
    }

    @Test("the corners of the card are as round as the md radius says")
    func cornersFollowTheTheme() throws {
        let banner = Banner("Dictation is off.")
        let theme = try Probe.theme(.light)
        let round = Probe.picture(of: banner, size: canvas, scheme: .light)
        let square = Probe.picture(of: banner, size: canvas, scheme: .light, theme: Probe.rounded(.md, 0))
        // The first pixel of the square card, in its top left corner: on the card when the corner is square, and outside
        // it when the corner is round.
        let card = try #require(
            SnapshotSupport.extent(of: square, matching: theme.color(.surfaceRaised), tolerance: Probe.exact))
        let corner = (x: (card.minX + 0.25) / canvas.width, y: (card.minY + 0.25) / canvas.height)

        func distance(_ first: RGBAColor, _ second: RGBAColor) -> Double {
            max(abs(first.red - second.red), abs(first.green - second.green), abs(first.blue - second.blue))
        }
        let rounded = SnapshotSupport.pixel(of: round, atX: corner.x, y: corner.y)
        let squared = SnapshotSupport.pixel(of: square, atX: corner.x, y: corner.y)
        #expect(distance(squared, theme.color(.surfaceRaised)) <= Probe.exact, "\(squared)")
        #expect(distance(rounded, theme.color(.surfaceWindow)) <= Probe.exact, "\(rounded)")
    }
}
