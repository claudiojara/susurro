import AppKit
import AudioIO
import Domain
import Foundation
import Persistence
import Pipeline
import Presentation

extension HistoryDependencies {
    /// The real history: a SQLite database in the app's folder of Application Support, audio files read as CAF and deleted
    /// from the disk, the system clipboard, and the speech recognizer for the retry. Touching the database and the disk
    /// is covered by the manual check, not by tests.
    ///
    /// - Parameter recognizer: The recognizer the retry transcribes with.
    /// - Parameter sleep: Pauses on the app's clock, which bounds a retry's transcription.
    @MainActor
    static func live(
        recognizer: any SpeechRecognizer, sleep: @escaping @Sendable (Duration) async throws -> Void
    ) -> HistoryDependencies {
        HistoryDependencies(
            repository: openRepository(),
            deleter: FileSystemAudioDeleter(),
            loader: CAFClipLoader(),
            clipboard: SystemClipboardWriter(),
            reprocessor: WholeClipReprocessor(
                recognizer: recognizer, providerID: ASRProviderID("parakeet-v3"), sleep: sleep),
            dates: SystemDateSource(),
            window: { HistoryWindowController(model: $0, themes: $1) }
        )
    }

    /// Where the history database lives: `History.sqlite` in the app's folder of Application Support.
    static var databaseURL: URL {
        URL.applicationSupportDirectory.appending(path: "Susurro/History.sqlite", directoryHint: .notDirectory)
    }

    /// Opens the history database. If it cannot be opened (a damaged file, a read-only disk), the app still runs, with a
    /// history that lives in memory until it quits, rather than not starting.
    private static func openRepository() -> any HistoryRepository {
        do {
            return try GRDBHistoryRepository(path: databaseURL.path)
        } catch {
            do {
                return try GRDBHistoryRepository.inMemory()
            } catch {
                preconditionFailure("The in-memory history could not be created: \(error)")
            }
        }
    }
}

/// Puts text on the system clipboard.
struct SystemClipboardWriter: ClipboardWriting {
    func copy(_ text: String) async {
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}
