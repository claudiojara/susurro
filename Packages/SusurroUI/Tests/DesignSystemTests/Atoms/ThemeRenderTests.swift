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

    @Test(
        "two themes that differ only in accent draw the accent views differently and the others alike",
        arguments: Subject.allCases)
    fileprivate func differentThemeDifferentRender(subject: Subject) {
        for scheme in [ColorScheme.light, .dark] {
            let standard = SnapshotSupport.pngData(of: subject.view, size: size, theme: .default, scheme: scheme)
            let other = SnapshotSupport.pngData(of: subject.view, size: size, theme: otherAccent, scheme: scheme)
            #expect((standard != other) == subject.usesAccent, "\(subject) in \(scheme)")
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
