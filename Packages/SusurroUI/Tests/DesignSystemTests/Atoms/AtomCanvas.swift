import SwiftUI
import UITestSupport

@testable import DesignSystem

/// The canvas each atom gallery is drawn on for its snapshot. It is small on purpose (see `AtomCanvasTests`), so a
/// change to a small view is a large part of the picture.
enum AtomCanvas: CaseIterable, Sendable {
    case labels, icons, pills, statusDots, levelBars, buttons

    var size: CGSize {
        switch self {
        case .labels: CGSize(width: 160, height: 336)
        case .icons: CGSize(width: 250, height: 110)
        case .pills: CGSize(width: 120, height: 220)
        case .statusDots: CGSize(width: 160, height: 60)
        case .levelBars: CGSize(width: 200, height: 212)
        case .buttons: CGSize(width: 320, height: 168)
        }
    }

    /// Whether the gallery stretches to the width it is given, so that the canvas sets the width.
    var fillsItsWidth: Bool { self == .levelBars }

    @MainActor var gallery: AnyView {
        switch self {
        case .labels: AnyView(TextLabel.Gallery())
        case .icons: AnyView(Icon.Gallery())
        case .pills: AnyView(Pill.Gallery())
        case .statusDots: AnyView(StatusDot.Gallery())
        case .levelBars: AnyView(LevelBar.Gallery())
        case .buttons: AnyView(ActionButton.Gallery())
        }
    }

    @MainActor func contentSize(scheme: ColorScheme) -> CGSize {
        SnapshotSupport.idealSize(of: gallery, scheme: scheme)
    }

    /// How many pixels change when the smallest variant in the gallery is painted in another tint, which is the least a
    /// recolored view of this gallery changes. A canvas that lets more than two thirds of that differ would let such a
    /// recoloring pass unseen.
    @MainActor func recoloredPixels(scheme: ColorScheme) -> Int {
        switch self {
        case .labels:
            changed(
                TextLabel("caption", style: .caption, tint: .neutral),
                TextLabel("caption", style: .caption, tint: .accent), scheme)
        case .icons:
            changed(
                Icon("mic.fill", style: .caption, tint: .neutral), Icon("mic.fill", style: .caption, tint: .accent),
                scheme)
        case .pills:
            changed(Pill("neutral", tint: .neutral), Pill("neutral", tint: .accent), scheme)
        case .statusDots:
            changed(StatusDot(.neutral), StatusDot(.accent), scheme)
        case .levelBars:
            changed(
                LevelBar(level: 0.25, tint: .neutral, label: "Level").frame(
                    width: size.width - 2 * SnapshotSupport.margin()),
                LevelBar(level: 0.25, tint: .accent, label: "Level").frame(
                    width: size.width - 2 * SnapshotSupport.margin()),
                scheme)
        case .buttons:
            changed(
                ActionButton("secondary", kind: .secondary) {},
                ActionButton("secondary", kind: .secondary) {}.disabled(true), scheme)
        }
    }

    @MainActor private func changed<A: View, B: View>(_ first: A, _ second: B, _ scheme: ColorScheme) -> Int {
        let size = CGSize(width: 140, height: 70)
        return SnapshotSupport.differingPixels(
            SnapshotSupport.cgImage(of: first, size: size, scheme: scheme),
            SnapshotSupport.cgImage(of: second, size: size, scheme: scheme), tolerance: 0.02)
    }
}
