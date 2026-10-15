import Domain
import Foundation
import Pipeline
import SusurroUI

/// Every word the history screen shows, in one place: the view model writes none of its own. The sentences that depend on
/// a dictation take the facts from the record and never its text, since an error can quote what was said. The sentences
/// are in the string catalog of the module (`Localizable.xcstrings`), under the keys written here.
enum HistoryCopy {
    static var title: String { L10n.string("history.title", "History") }
    static var emptyMessage: String { L10n.string("history.empty", "No dictations yet. Hold the hotkey and speak.") }
    static var loadMore: String { L10n.string("history.loadMore", "Show older") }
    static var deleteAll: String { L10n.string("history.deleteAll", "Delete all…") }
    static var dismiss: String { L10n.string("history.dismiss", "Dismiss") }

    // MARK: Rows

    static func statusLabel(_ status: HistoryRowStatus) -> String {
        switch status {
        case .processing: L10n.string("history.status.processing", "Processing…")
        case .succeeded: L10n.string("history.status.succeeded", "Done")
        case .noSpeech: L10n.string("history.status.noSpeech", "No speech")
        case .failed: L10n.string("history.status.failed", "Failed")
        case .cancelled: L10n.string("history.status.cancelled", "Cancelled")
        }
    }

    static func title(of action: HistoryActionKind) -> String {
        switch action {
        case .copyRaw: L10n.string("history.action.copyRaw", "Copy raw")
        case .copyCleaned: L10n.string("history.action.copyCleaned", "Copy cleaned")
        case .retry: L10n.string("history.action.retry", "Retry")
        case .delete: L10n.string("history.action.delete", "Delete")
        }
    }

    static var audioExpiredDetail: String { L10n.string("history.audioExpired", "Audio expired") }
    static var retryAudioExpired: String { L10n.string("history.retry.audioExpired", "Audio expired after 7 days.") }
    static var retryNoAudio: String { L10n.string("history.retry.noAudio", "There is no audio to run again.") }
    static var retryCommand: String { L10n.string("history.retry.command", "A command cannot be run again.") }

    /// "Today, 14:32" and "Yesterday, 18:02", with the time already formatted.
    static func today(_ time: String) -> String { L10n.string("history.date.today", "Today, \(time)") }
    static func yesterday(_ time: String) -> String { L10n.string("history.date.yesterday", "Yesterday, \(time)") }

    /// The text of a dictation that has none yet, by how it stands.
    static func placeholder(for status: HistoryRowStatus) -> String {
        switch status {
        case .processing: L10n.string("history.placeholder.processing", "Working on it.")
        case .noSpeech: L10n.string("history.placeholder.noSpeech", "No speech was found.")
        case .succeeded, .failed, .cancelled: L10n.string("history.placeholder.none", "No text yet.")
        }
    }

    // MARK: Notes

    /// What went wrong, by the name the pipeline recorded. A name this version does not know still gets a sentence.
    static func failure(_ name: String?) -> String {
        switch name {
        case DictationRecord.interruptedFailure:
            L10n.string("history.failure.interrupted", "Susurro quit before this dictation was finished.")
        case RetryService.audioUnreadableFailure:
            L10n.string("history.failure.audioUnreadable", "The audio could not be read.")
        case "timedOut.transcription", "timedOut.readiness":
            L10n.string("history.failure.timedOut", "The transcription took too long.")
        case "recognitionFailed":
            L10n.string("history.failure.recognition", "The speech model could not transcribe it.")
        case "recognizerUnavailable", "recognizerNotInstalled":
            L10n.string("history.failure.recognizer", "The speech model was not available.")
        case "captureFailed": L10n.string("history.failure.capture", "The recording failed.")
        case "commandNoResult":
            L10n.string(
                "history.failure.commandNoResult", "The model gave no usable result, so the text was left as is.")
        default: L10n.string("history.failure.other", "It did not finish.")
        }
    }

    static var command: String {
        L10n.string("history.note.command", "A command over a selection. The selection and the result are not kept.")
    }
    static var retryHint: String { L10n.string("history.note.retry", "Retry to run it again.") }
    static var cancelled: String { L10n.string("history.note.cancelled", "You cancelled this dictation.") }
    static var cancelledAudioKept: String {
        L10n.string("history.note.cancelledAudioKept", "You cancelled this dictation. The audio is kept.")
    }
    static var notInserted: String {
        L10n.string("history.note.notInserted", "The text was not inserted. Copy it from here.")
    }
    static var leftOnClipboard: String {
        L10n.string("history.note.clipboard", "The text was left on the clipboard.")
    }
    static var cleanupFellBack: String {
        L10n.string("history.note.cleanupFellBack", "Cleanup did not run, so this is the raw text.")
    }

    // MARK: Questions and errors

    static var deleteOneQuestion: String {
        L10n.string("history.question.deleteOne", "Delete this dictation and its audio? This cannot be undone.")
    }
    static var deleteAllQuestion: String {
        L10n.string("history.question.deleteAll", "Delete every dictation and its audio? This cannot be undone.")
    }
    static var confirmDelete: String { L10n.string("history.question.confirm", "Delete") }
    static var keep: String { L10n.string("history.question.keep", "Keep") }

    static func audioNotDeleted(count: Int) -> String {
        count == 1
            ? L10n.string(
                "history.error.audioNotDeleted.one",
                "The audio of 1 dictation could not be deleted, so the dictation was kept. Try again.")
            : L10n.string(
                "history.error.audioNotDeleted.other",
                "The audio of \(count) dictations could not be deleted, so those dictations were kept. Try again.")
    }

    static var nothingToCopy: String {
        L10n.string("history.error.nothingToCopy", "There is no text of that kind to copy.")
    }
    static var recordGone: String {
        L10n.string("history.error.recordGone", "That dictation is no longer in the history.")
    }
    static var historyUnreadable: String { L10n.string("history.error.unreadable", "The history could not be read.") }
    static var historyNotSaved: String {
        L10n.string("history.error.notSaved", "The change could not be saved to the history.")
    }

    static func refusal(_ refusal: RetryRefusal) -> String {
        switch refusal {
        case .recordNotFound: recordGone
        case .audioExpired: retryAudioExpired
        case .noAudio: retryNoAudio
        case .command: retryCommand
        case .stillProcessing: L10n.string("history.refusal.processing", "That dictation is still being processed.")
        case .alreadyRetrying:
            L10n.string("history.refusal.retrying", "A retry of that dictation is already running.")
        }
    }
}
