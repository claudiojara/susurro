import SwiftUI
import Testing
import UITestSupport

@testable import SusurroUI

/// The canvas each overlay state is drawn on for its snapshot. A picture matches when 99.9 % of its pixels do, so a canvas
/// is just big enough for what it shows (`OverlayCanvasTests`), and its size is written here, not measured: a canvas that
/// followed the fonts of the machine would give a picture of another size on another macOS.
enum OverlayCanvas: CaseIterable, Sendable, CustomTestStringConvertible {
    case starting, recordingHold, recordingHandsFree, transcribing, loadingModel, polishing, inserted, notice, error

    var testDescription: String { "\(self)" }

    /// The overlay width of the default theme, plus the margin of the canvas.
    private static let width: CGFloat = 412

    var size: CGSize {
        switch self {
        case .starting: CGSize(width: Self.width, height: 82)
        case .recordingHold: CGSize(width: Self.width, height: 118)
        case .recordingHandsFree: CGSize(width: Self.width, height: 136)
        case .transcribing: CGSize(width: Self.width, height: 82)
        case .loadingModel: CGSize(width: Self.width, height: 96)
        case .polishing: CGSize(width: Self.width, height: 82)
        case .inserted: CGSize(width: Self.width, height: 82)
        case .notice: CGSize(width: Self.width, height: 100)
        case .error: CGSize(width: Self.width, height: 100)
        }
    }

    #if DEBUG
        private var fixture: OverlayFixtures.Fixture {
            switch self {
            case .starting: .starting
            case .recordingHold: .recordingHold
            case .recordingHandsFree: .recordingHandsFree
            case .transcribing: .transcribing
            case .loadingModel: .loadingModel
            case .polishing: .polishing
            case .inserted: .inserted
            case .notice: .notice
            case .error: .error
            }
        }

        @MainActor var state: OverlayViewState { OverlayFixtures.state(fixture) }

        @MainActor var view: AnyView {
            AnyView(OverlayHUD(state: state, level: OverlayFixtures.level))
        }
    #endif
}
