import Domain
import Foundation
import Pipeline
import SusurroUI

/// Every word the history screen shows, in one place: the view model writes none of its own. The sentences that depend on
/// a dictation take the facts from the record and never its text, since an error can quote what was said.
enum HistoryCopy {
    static let title = "History"
    static let emptyMessage = "No dictations yet. Hold the hotkey and speak."
    static let loadMore = "Show older"
    static let deleteAll = "Delete all…"
    static let dismiss = "Dismiss"

    // MARK: Rows

    static func statusLabel(_ status: HistoryRowStatus) -> String {
        switch status {
        case .processing: "Processing…"
        case .succeeded: "Done"
        case .noSpeech: "No speech"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }

    static func title(of action: HistoryActionKind) -> String {
        switch action {
        case .copyRaw: "Copy raw"
        case .copyCleaned: "Copy cleaned"
        case .retry: "Retry"
        case .delete: "Delete"
        }
    }

    static let audioExpiredDetail = "Audio expired"
    static let retryAudioExpired = "Audio expired after 7 days."
    static let retryNoAudio = "There is no audio to run again."

    /// The text of a dictation that has none yet, by how it stands.
    static func placeholder(for status: HistoryRowStatus) -> String {
        switch status {
        case .processing: "Working on it."
        case .noSpeech: "No speech was found."
        case .succeeded, .failed, .cancelled: "No text yet."
        }
    }

    // MARK: Notes

    /// What went wrong, by the name the pipeline recorded. A name this version does not know still gets a sentence.
    static func failure(_ name: String?) -> String {
        switch name {
        case DictationRecord.interruptedFailure: "Susurro quit before this dictation was finished."
        case RetryService.audioUnreadableFailure: "The audio could not be read."
        case "timedOut.transcription", "timedOut.readiness": "The transcription took too long."
        case "recognitionFailed": "The speech model could not transcribe it."
        case "recognizerUnavailable", "recognizerNotInstalled": "The speech model was not available."
        case "captureFailed": "The recording failed."
        default: "It did not finish."
        }
    }

    static let retryHint = "Retry to run it again."
    static let cancelled = "You cancelled this dictation."
    static let cancelledAudioKept = "You cancelled this dictation. The audio is kept."
    static let notInserted = "The text was not inserted. Copy it from here."
    static let leftOnClipboard = "The text was left on the clipboard."
    static let cleanupFellBack = "Cleanup did not run, so this is the raw text."

    // MARK: Questions and errors

    static let deleteOneQuestion = "Delete this dictation and its audio? This cannot be undone."
    static let deleteAllQuestion = "Delete every dictation and its audio? This cannot be undone."
    static let confirmDelete = "Delete"
    static let keep = "Keep"

    static func audioNotDeleted(count: Int) -> String {
        count == 1
            ? "The audio of 1 dictation could not be deleted, so the dictation was kept. Try again."
            : "The audio of \(count) dictations could not be deleted, so those dictations were kept. Try again."
    }

    static let nothingToCopy = "There is no text of that kind to copy."
    static let recordGone = "That dictation is no longer in the history."
    static let historyUnreadable = "The history could not be read."
    static let historyNotSaved = "The change could not be saved to the history."

    static func refusal(_ refusal: RetryRefusal) -> String {
        switch refusal {
        case .recordNotFound: recordGone
        case .audioExpired: retryAudioExpired
        case .noAudio: retryNoAudio
        case .stillProcessing: "That dictation is still being processed."
        case .alreadyRetrying: "A retry of that dictation is already running."
        }
    }
}
