// What the history views show in previews and in snapshot tests, in one place: the previews and the pictures draw the same
// states, so there is one list of them to keep. The words are the ones the app uses.
#if DEBUG

    import Foundation

    enum HistoryFixtures {
        /// The states a row can be in.
        enum Row: CaseIterable, Sendable {
            /// Done, with cleaned text.
            case succeeded
            /// Done, but the text never reached the app: the history is the only place it is.
            case notInserted
            /// Done, but the 7 days of audio are over, so it cannot be retried.
            case audioExpired
            case failed
            case processing
            case noSpeech
            case cancelled
        }

        /// The screens, each with the list and the notices it shows.
        enum Screen: CaseIterable, Sendable {
            case empty
            case populated
            case audioExpired
            case failed
            case processing
            /// A question stands before the deletion of one dictation.
            case confirming
            /// The audio of a dictation could not be deleted.
            case error
        }

        static func state(_ screen: Screen) -> HistoryViewState {
            switch screen {
            case .empty: state(rows: [], deleteAll: false)
            case .populated: state(rows: [row(.succeeded), row(.notInserted), row(.failed)], loadMore: true)
            case .audioExpired: state(rows: [row(.audioExpired)])
            case .failed: state(rows: [row(.failed)])
            case .processing: state(rows: [row(.processing), row(.succeeded)])
            case .confirming:
                state(
                    rows: [row(.succeeded)],
                    confirmation: HistoryConfirmation(
                        message: "Delete this dictation and its audio? This cannot be undone.", confirmTitle: "Delete",
                        cancelTitle: "Keep"))
            case .error:
                state(
                    rows: [row(.succeeded)],
                    error: "The audio of 1 dictation could not be deleted, so the dictation was kept. Try again.")
            }
        }

        static func rows(_ screen: Screen) -> [HistoryRowState] { state(screen).rows }

        static func row(_ row: Row) -> HistoryRowState {
            switch row {
            case .succeeded:
                make(
                    id: 1, status: .succeeded, label: "Done", timestamp: "Today, 14:32", detail: "Notes · 12 s",
                    text: "Hi Ana, I will send you the report tomorrow morning.", note: nil,
                    actions: [copyRaw, copyCleaned, retry(), delete])
            case .notInserted:
                make(
                    id: 2, status: .succeeded, label: "Done", timestamp: "Today, 14:10", detail: "Slack · 4 s",
                    text: "Can we move the call to Thursday?",
                    note: "The text was not inserted. Copy it from here.",
                    actions: [copyRaw, copyCleaned, retry(), delete])
            case .audioExpired:
                make(
                    id: 3, status: .succeeded, label: "Done", timestamp: "8 Oct, 09:15",
                    detail: "Mail · 31 s · Audio expired", text: "Thanks for the quick reply, that works for me.",
                    note: nil,
                    actions: [copyRaw, copyCleaned, retry(unavailable: "Audio expired after 7 days."), delete])
            case .failed:
                make(
                    id: 4, status: .failed, label: "Failed", timestamp: "Yesterday, 18:02", detail: "Notes · 9 s",
                    text: "No text yet.", note: "Transcription took too long. Retry to run it again.",
                    actions: [retry(), delete])
            case .processing:
                make(
                    id: 5, status: .processing, label: "Processing…", timestamp: "Today, 14:33", detail: "Notes · 6 s",
                    text: "Working on it.", note: nil, actions: [])
            case .noSpeech:
                make(
                    id: 6, status: .noSpeech, label: "No speech", timestamp: "Today, 13:50", detail: "Notes · 2 s",
                    text: "No speech was found.", note: nil, actions: [retry(), delete])
            case .cancelled:
                make(
                    id: 7, status: .cancelled, label: "Cancelled", timestamp: "Today, 13:20", detail: "Notes · 5 s",
                    text: "No text yet.", note: "You cancelled this dictation. The audio is kept.",
                    actions: [retry(), delete])
            }
        }

        // MARK: Building

        private static func state(
            rows: [HistoryRowState], deleteAll: Bool = true, loadMore: Bool = false,
            confirmation: HistoryConfirmation? = nil, error: String? = nil
        ) -> HistoryViewState {
            HistoryViewState(
                title: "History", rows: rows, emptyMessage: "No dictations yet. Hold the hotkey and speak.",
                loadMoreTitle: loadMore ? "Show older" : nil, deleteAllTitle: deleteAll ? "Delete all…" : nil,
                confirmation: confirmation, errorMessage: error, dismissErrorTitle: "Dismiss")
        }

        private static func make(
            id: Int, status: HistoryRowStatus, label: String, timestamp: String, detail: String, text: String,
            note: String?, actions: [HistoryRowAction]
        ) -> HistoryRowState {
            HistoryRowState(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(id)")!, status: status, statusLabel: label,
                timestamp: timestamp, detail: detail, text: text, note: note, actions: actions)
        }

        private static let copyRaw = HistoryRowAction(kind: .copyRaw, title: "Copy raw")
        private static let copyCleaned = HistoryRowAction(kind: .copyCleaned, title: "Copy cleaned")
        private static let delete = HistoryRowAction(kind: .delete, title: "Delete")

        private static func retry(unavailable: String? = nil) -> HistoryRowAction {
            HistoryRowAction(kind: .retry, title: "Retry", unavailableReason: unavailable)
        }
    }

#endif
