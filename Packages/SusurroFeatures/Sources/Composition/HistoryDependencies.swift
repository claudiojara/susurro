import CoreTestSupport
import Domain
import Foundation
import Presentation

/// What the dictation history needs from the system: where the records live, how audio files are deleted and read back,
/// how text reaches the clipboard, how a recording is run through the pipeline again, and the history window. The live
/// set is in `HistoryDependencies+Live.swift`; `preview()` is the set on the fakes.
public struct HistoryDependencies {
    /// The history of the dictations. The dictation pipeline writes its records here, and the screen, the retention job,
    /// and the retry read them.
    public var repository: any HistoryRepository
    public var deleter: any AudioFileDeleting
    public var loader: any AudioClipLoading
    public var clipboard: any ClipboardWriting
    /// Runs a stored recording through the pipeline again, for the history's retry. It never inserts.
    public var reprocessor: any DictationReprocessing
    public var dates: any DateSource
    /// Makes the window of the history, which shows the view model in the theme.
    public var window: @MainActor (HistoryViewModel, ThemeModel) -> any HistorySurface

    public init(
        repository: any HistoryRepository,
        deleter: any AudioFileDeleting,
        loader: any AudioClipLoading,
        clipboard: any ClipboardWriting,
        reprocessor: any DictationReprocessing,
        dates: any DateSource,
        window: @escaping @MainActor (HistoryViewModel, ThemeModel) -> any HistorySurface
    ) {
        self.repository = repository
        self.deleter = deleter
        self.loader = loader
        self.clipboard = clipboard
        self.reprocessor = reprocessor
        self.dates = dates
        self.window = window
    }

    /// The history on the fakes: it lives in memory, deletes nothing, copies to nowhere, and shows no window.
    public static func preview() -> HistoryDependencies {
        HistoryDependencies(
            repository: InMemoryHistoryRepository(),
            deleter: FakeAudioFileDeleter(),
            loader: FakeAudioClipLoader(),
            clipboard: FakeClipboardWriter(),
            reprocessor: FakeDictationReprocessor(text: "Preview dictation"),
            dates: SystemDateSource(),
            window: { _, _ in NoHistoryWindow() }
        )
    }
}

/// A history window that shows nothing.
@MainActor
private struct NoHistoryWindow: HistorySurface {
    func show() {}
}
