import SwiftUI
import Testing
import UITestSupport

@testable import DesignSystem

@MainActor
@Suite("Theme render")
struct ThemeRenderTests {
    /// A view and whether it draws anything in the accent color.
    fileprivate enum Subject: CaseIterable, CustomTestStringConvertible {
        case accentPill, accentDot, accentBar, primaryButton
        case label, neutralPill, errorDot, recordingBar, secondaryButton

        var usesAccent: Bool {
            switch self {
            case .accentPill, .accentDot, .accentBar, .primaryButton: true
            case .label, .neutralPill, .errorDot, .recordingBar, .secondaryButton: false
            }
        }

        var testDescription: String { "\(self)" }

        @ViewBuilder var view: some View {
            switch self {
            case .accentPill: Pill("Accent", tint: .accent)
            case .accentDot: StatusDot(.accent)
            case .accentBar: LevelBar(level: 0.5, tint: .accent, label: "Level")
            case .primaryButton: ActionButton("Save", kind: .primary) {}
            case .label: TextLabel("Recording", style: .headline)
            case .neutralPill: Pill("Neutral")
            case .errorDot: StatusDot(.error)
            case .recordingBar: LevelBar(level: 0.5, tint: .recording, label: "Level")
            case .secondaryButton: ActionButton("Cancel", kind: .secondary) {}
            }
        }
    }

    /// The default theme with only the accent color changed.
    private let otherAccent: Theme = {
        var theme = Theme.default
        theme.palette["testAccent"] = PaletteColor(
            light: RGBAColor(red: 0.9, green: 0.1, blue: 0.6), dark: RGBAColor(red: 1, green: 0.4, blue: 0.8))
        theme.colors["accent.primary"] = "testAccent"
        return theme
    }()

    private let size = CGSize(width: 160, height: 80)

    /// The accent color of a theme in an appearance.
    private func accent(of theme: Theme, _ appearance: Appearance) throws -> RGBAColor {
        try theme.resolved(for: appearance).color(.accentPrimary)
    }

    @Test(
        "two themes that differ only in accent change only what is painted in the accent, and change nothing else",
        arguments: Subject.allCases)
    fileprivate func onlyTheAccentChanges(subject: Subject) throws {
        for (scheme, appearance) in [(ColorScheme.light, Appearance.light), (.dark, .dark)] {
            let before = SnapshotSupport.cgImage(of: subject.view, size: size, theme: .default, scheme: scheme)
            let after = SnapshotSupport.cgImage(of: subject.view, size: size, theme: otherAccent, scheme: scheme)
            let changes = SnapshotSupport.pixelChanges(from: before, to: after)
            guard subject.usesAccent else {
                #expect(changes.isEmpty, "\(subject) in \(scheme): \(changes.count) pixels changed")
                continue
            }
            // A pixel that is a share `s` of accent and the rest of something else changes by `s` times the change of
            // the accent, in all three channels at once. A pixel that changed for another reason would not.
            let from = try accent(of: .default, appearance)
            let to = try accent(of: otherAccent, appearance)
            let shift = (red: to.red - from.red, green: to.green - from.green, blue: to.blue - from.blue)
            let pivot = max(abs(shift.red), abs(shift.green), abs(shift.blue))
            #expect(pivot > 0.2, "the two accents are too close to tell their pixels apart")
            #expect(!changes.isEmpty, "\(subject) in \(scheme): the accent changed nothing")
            var shares: [Double] = []
            for change in changes {
                let share =
                    (abs(shift.red) == pivot
                        ? change.red / shift.red
                        : abs(shift.green) == pivot ? change.green / shift.green : change.blue / shift.blue)
                shares.append(share)
                let rounding = 2.0 / 255
                #expect(
                    abs(change.red - share * shift.red) <= rounding, "\(subject) in \(scheme): not an accent change")
                #expect(
                    abs(change.green - share * shift.green) <= rounding, "\(subject) in \(scheme): not an accent change"
                )
                #expect(
                    abs(change.blue - share * shift.blue) <= rounding, "\(subject) in \(scheme): not an accent change")
            }
            #expect(shares.allSatisfy { $0 > -0.02 && $0 < 1.02 }, "\(subject) in \(scheme): a share outside 0 to 1")
            #expect(shares.contains { $0 > 0.98 }, "\(subject) in \(scheme): no pixel is all accent")
        }
    }

    @Test("rendering one state twice gives the same bytes", arguments: Subject.allCases)
    fileprivate func renderingIsStable(subject: Subject) {
        let first = SnapshotSupport.pngData(of: subject.view, size: size, theme: .default, scheme: .light)
        let second = SnapshotSupport.pngData(of: subject.view, size: size, theme: .default, scheme: .light)
        #expect(!first.isEmpty)
        #expect(first == second)
    }

    @Test("light and dark appearance draw differently")
    func appearanceChangesTheRender() {
        let light = SnapshotSupport.pngData(of: TextLabel("Ready"), size: size, theme: .default, scheme: .light)
        let dark = SnapshotSupport.pngData(of: TextLabel("Ready"), size: size, theme: .default, scheme: .dark)
        #expect(light != dark)
    }

    @Test("the picture has the size asked for, at two pixels to the point")
    func rendersAtAFixedScale() {
        let image = SnapshotSupport.cgImage(of: TextLabel("Ready"), size: size, theme: .default, scheme: .light)
        #expect(image.width == 320)
        #expect(image.height == 160)
    }

    @Test("a view is drawn with motion off")
    func rendersWithMotionOff() {
        struct Probe: View {
            @Environment(\.motionEnabled) private var motionEnabled
            let seen: Seen

            var body: some View {
                seen.motionEnabled = motionEnabled
                return Color.clear
            }
        }
        final class Seen { var motionEnabled: Bool? }
        let seen = Seen()
        _ = SnapshotSupport.pngData(of: Probe(seen: seen), size: size, theme: .default, scheme: .light)
        #expect(seen.motionEnabled == false)
    }
}
