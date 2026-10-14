import SwiftUI
import Testing
import UITestSupport

@testable import SusurroUI

/// The canvas each history view is drawn on for its snapshot. A picture matches when 99.9 % of its pixels do, so a canvas
/// is just big enough for what it shows (`HistoryCanvasTests`), and its size is written here, not measured: a canvas that
/// followed the fonts of the machine would give a picture of another size on another macOS.
enum HistoryCanvas: CaseIterable, Sendable, CustomTestStringConvertible {
    case rowSucceeded, rowNotInserted, rowAudioExpired, rowFailed, rowProcessing
    case noticeConfirm
    case listPopulated
    case screenEmpty, screenPopulated, screenAudioExpired, screenFailed, screenProcessing, screenConfirming

    var testDescription: String { "\(self)" }

    /// The width a row has inside the history screen, plus the margin of the canvas.
    private static let rowWidth: CGFloat = 568

    var size: CGSize {
        switch self {
        case .rowSucceeded: CGSize(width: Self.rowWidth, height: 163)
        case .rowNotInserted: CGSize(width: Self.rowWidth, height: 185)
        case .rowAudioExpired: CGSize(width: Self.rowWidth, height: 185)
        case .rowFailed: CGSize(width: Self.rowWidth, height: 185)
        case .rowProcessing: CGSize(width: Self.rowWidth, height: 123)
        case .noticeConfirm: CGSize(width: Self.rowWidth, height: 115)
        case .listPopulated: CGSize(width: Self.rowWidth, height: 481)
        case .screenEmpty: CGSize(width: Self.rowWidth, height: 138)
        case .screenPopulated: CGSize(width: Self.rowWidth, height: 617)
        case .screenAudioExpired: CGSize(width: Self.rowWidth, height: 281)
        case .screenFailed: CGSize(width: Self.rowWidth, height: 281)
        case .screenProcessing: CGSize(width: Self.rowWidth, height: 356)
        case .screenConfirming: CGSize(width: Self.rowWidth, height: 356)
        }
    }

    @MainActor var view: AnyView {
        switch self {
        case .rowSucceeded: row(.succeeded)
        case .rowNotInserted: row(.notInserted)
        case .rowAudioExpired: row(.audioExpired)
        case .rowFailed: row(.failed)
        case .rowProcessing: row(.processing)
        case .noticeConfirm:
            AnyView(
                HistoryNotice(
                    "Delete this dictation and its audio? This cannot be undone.", symbol: "trash.fill", tint: .warning,
                    buttons: [
                        .init(title: "Keep", kind: .secondary, action: {}),
                        .init(title: "Delete", kind: .destructive, action: {}),
                    ]))
        case .listPopulated: AnyView(HistoryList(HistoryFixtures.rows(.populated)) { _, _ in })
        case .screenEmpty: screen(.empty)
        case .screenPopulated: screen(.populated)
        case .screenAudioExpired: screen(.audioExpired)
        case .screenFailed: screen(.failed)
        case .screenProcessing: screen(.processing)
        case .screenConfirming: screen(.confirming)
        }
    }

    @MainActor private func row(_ fixture: HistoryFixtures.Row) -> AnyView {
        AnyView(HistoryRow(HistoryFixtures.row(fixture)) { _ in })
    }

    @MainActor private func screen(_ fixture: HistoryFixtures.Screen) -> AnyView {
        AnyView(
            HistoryScreen(
                state: HistoryFixtures.state(fixture), onAction: { _, _ in }, onLoadMore: {}, onDeleteAll: {},
                onConfirm: {}, onCancel: {}, onDismissError: {}))
    }
}
