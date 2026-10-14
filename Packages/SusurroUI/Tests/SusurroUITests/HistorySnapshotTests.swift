import SwiftUI
import Testing
import UITestSupport

@testable import SusurroUI

/// One picture per view and appearance, each on a canvas just big enough for it (`HistoryCanvas`). The references are
/// recorded on the CI image (`record-snapshots`), never here, and `make test` skips these suites by their name.
@MainActor
@Suite("History snapshots")
struct HistorySnapshotTests {
    nonisolated private static let rows: [HistoryCanvas] = [
        .rowSucceeded, .rowNotInserted, .rowAudioExpired, .rowFailed, .rowProcessing,
    ]

    nonisolated private static let lists: [HistoryCanvas] = [.listPopulated]
    nonisolated private static let notices: [HistoryCanvas] = [.noticeConfirm]
    nonisolated private static let screens: [HistoryCanvas] = [
        .screenEmpty, .screenPopulated, .screenAudioExpired, .screenFailed, .screenProcessing, .screenConfirming,
    ]

    @Test("a history row in each state", arguments: rows, Probe.schemes)
    func rows(canvas: HistoryCanvas, scheme: ColorScheme) {
        assertViewSnapshot(of: canvas.view, size: canvas.size, scheme: scheme, named: "\(canvas)-\(scheme.pictureName)")
    }

    @Test("the question before a deletion", arguments: notices, Probe.schemes)
    func notices(canvas: HistoryCanvas, scheme: ColorScheme) {
        assertViewSnapshot(of: canvas.view, size: canvas.size, scheme: scheme, named: "\(canvas)-\(scheme.pictureName)")
    }

    @Test("the list with a done, a not inserted, and a failed dictation", arguments: lists, Probe.schemes)
    func lists(canvas: HistoryCanvas, scheme: ColorScheme) {
        assertViewSnapshot(of: canvas.view, size: canvas.size, scheme: scheme, named: "\(canvas)-\(scheme.pictureName)")
    }

    @Test(
        "the history screen empty, populated, with expired audio, failed, processing, and asking before a deletion",
        arguments: screens, Probe.schemes)
    func screens(canvas: HistoryCanvas, scheme: ColorScheme) {
        assertViewSnapshot(of: canvas.view, size: canvas.size, scheme: scheme, named: "\(canvas)-\(scheme.pictureName)")
    }
}
