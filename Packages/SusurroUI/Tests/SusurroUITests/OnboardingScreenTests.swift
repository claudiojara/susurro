import SwiftUI
import Testing
import UITestSupport

@testable import DesignSystem
@testable import SusurroUI

/// What the onboarding screen paints, read from its pixels and its size, in light and dark.
@MainActor
@Suite("Onboarding screen")
struct OnboardingScreenTests {
    private func screen(_ state: OnboardingViewState) -> OnboardingScreen {
        OnboardingScreen(state: state, onAction: { _, _ in }, onRecheck: {}, onDone: {})
    }

    private func state(_ fixture: OnboardingFixtures.Screen) -> OnboardingViewState {
        OnboardingFixtures.state(fixture)
    }

    private func width(of view: some View, theme: Theme = .default) -> CGFloat {
        SnapshotSupport.idealSize(of: view, theme: theme, scheme: .light).width
    }

    private func canvas(for view: some View) -> CGSize {
        let size = SnapshotSupport.idealSize(of: view, scheme: .light)
        let margin = SnapshotSupport.margin()
        return CGSize(width: size.width + 2 * margin, height: size.height + 2 * margin)
    }

    // MARK: Layout

    @Test(
        "the screen is as wide as the onboarding width of the theme, whatever the text says", arguments: [440.0, 520.0])
    func widthIsTheToken(points: Double) {
        var theme = Theme.default
        theme.layout[LayoutToken.onboardingWidth.rawValue] = points

        #expect(abs(width(of: screen(state(.fresh)), theme: theme) - points) < 0.01)
        #expect(abs(width(of: screen(state(.allGranted)), theme: theme) - points) < 0.01)
    }

    @Test("the default theme gives the onboarding a width that fits its rows")
    func defaultWidth() throws {
        #expect(try Probe.theme(.light).layout(.onboardingWidth) == 440)
    }

    @Test("the banner is there when a required permission is missing, and is not when nothing is")
    func bannerFollowsTheMessage() {
        let off = state(.fresh)
        let withoutMessage = OnboardingViewState(
            rows: off.rows, isDoneEnabled: off.isDoneEnabled, restrictionMessage: nil)

        let with = Probe.height(of: screen(off), width: 440)
        let without = Probe.height(of: screen(withoutMessage), width: 440)

        #expect(with > without + 30, "\(with) against \(without)")
    }

    @Test("a row more makes the screen taller by the height of the row and the space before it")
    func rowsAreInTheChecklist() {
        let two = state(.fresh)
        let four = OnboardingViewState(
            rows: OnboardingFixtures.rows(.withOptional), isDoneEnabled: true, restrictionMessage: nil)
        let twoWithout = OnboardingViewState(rows: two.rows, isDoneEnabled: true, restrictionMessage: nil)

        #expect(Probe.height(of: screen(four), width: 440) > Probe.height(of: screen(twoWithout), width: 440) + 100)
    }

    // MARK: Colors

    @Test("the banner paints in the warning color when dictation is off, and nothing is warned about when it is not")
    func warningColor() throws {
        for scheme in Probe.schemes {
            let theme = try Probe.theme(scheme)
            let off = screen(state(.fresh))
            let on = screen(state(.allGranted))

            let warned = SnapshotSupport.extent(
                of: Probe.picture(of: off, size: canvas(for: off), scheme: scheme),
                matching: theme.color(.statusWarning), tolerance: Probe.exact)
            let calm = SnapshotSupport.extent(
                of: Probe.picture(of: on, size: canvas(for: on), scheme: scheme),
                matching: theme.color(.statusWarning), tolerance: Probe.exact)

            #expect(warned != nil, "the banner in \(scheme)")
            #expect(calm == nil, "nothing is warned about in \(scheme): \(String(describing: calm))")
        }
    }

    @Test("Done is the main button once it is enabled, and is quiet while it is not", arguments: [true, false])
    func doneButton(isEnabled: Bool) throws {
        let granted = state(.allGranted)
        let state = OnboardingViewState(rows: granted.rows, isDoneEnabled: isEnabled, restrictionMessage: nil)
        for scheme in Probe.schemes {
            let theme = try Probe.theme(scheme)
            let view = screen(state)

            // Allowed rows paint in the success color, so the accent is only the Done button.
            let filled = SnapshotSupport.extent(
                of: Probe.picture(of: view, size: canvas(for: view), scheme: scheme),
                matching: theme.color(.accentPrimary), tolerance: Probe.exact)

            let isFilled = (filled?.width ?? 0) > 40
            #expect(isFilled == isEnabled, "enabled \(isEnabled) in \(scheme): \(String(describing: filled))")
        }
    }

    @Test("Done is at the right end of the foot of the screen, inside the padding")
    func doneIsAtTheFoot() throws {
        let view = screen(state(.allGranted))
        let size = canvas(for: view)
        let theme = try Probe.theme(.light)

        let done = try #require(
            SnapshotSupport.extent(
                of: Probe.picture(of: view, size: size, scheme: .light), matching: theme.color(.accentPrimary),
                tolerance: Probe.exact))

        let edge = size.width - SnapshotSupport.margin() - theme.spacing(.xl)
        #expect(abs(done.maxX - edge) <= 3, "\(done) against the edge at \(edge)")
        #expect(done.minY > size.height / 2, "\(done)")
    }

    @Test("the screen sits on the window color, and Check again is at the left end of the foot")
    func windowAndCheckAgain() throws {
        for scheme in Probe.schemes {
            let theme = try Probe.theme(scheme)
            let view = screen(state(.allGranted))
            let size = canvas(for: view)
            let picture = Probe.picture(of: view, size: size, scheme: scheme)
            let margin = SnapshotSupport.margin()
            let inset = theme.spacing(.xl)

            // The padding at the top left corner of the screen shows the window color of the theme, not a card's.
            let padding = SnapshotSupport.pixel(
                of: picture, atX: (margin + 4) / size.width, y: (margin + 4) / size.height)
            let window = theme.color(.surfaceWindow)
            #expect(
                max(abs(padding.red - window.red), abs(padding.green - window.green), abs(padding.blue - window.blue))
                    <= Probe.exact, "\(padding) in \(scheme)")

            // The title of Check again is in the plain text color, in the foot to the left of Done.
            let foot = CGRect(
                x: margin + inset, y: size.height - margin - inset - 34, width: 120, height: 34)
            #expect(Probe.isPainted(theme.color(.textPrimary), in: picture, region: foot), "the foot in \(scheme)")
        }
    }
}
