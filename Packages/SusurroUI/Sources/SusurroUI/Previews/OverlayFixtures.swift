#if DEBUG

    /// The states the overlay can be in, each with the words the app uses. The previews and the snapshot tests draw the
    /// same ones, so there is one list to keep.
    enum OverlayFixtures {
        enum Fixture: CaseIterable, Hashable {
            case starting, recordingHold, recordingHandsFree, transcribing, loadingModel, polishing, inserted, notice
            case error
        }

        static func state(_ fixture: Fixture) -> OverlayViewState {
            switch fixture {
            case .starting: .starting(text: "Getting ready…")
            case .recordingHold: .recording(handsFree: false, text: "Listening…", hint: nil)
            case .recordingHandsFree:
                .recording(
                    handsFree: true, text: "Listening…", hint: "Press the shortcut again to stop. Esc cancels.")
            case .transcribing: .transcribing(text: "Transcribing…", progress: nil)
            case .loadingModel: .transcribing(text: "Preparing the speech model… 40%", progress: 0.4)
            case .polishing: .polishing(text: "Polishing…")
            case .inserted: .inserted(text: "Pasted")
            case .notice:
                .notice(symbol: "doc.on.clipboard", text: "Copied to the clipboard. Paste it with Command-V.")
            case .error:
                .error(text: "Microphone access is off. Open the Susurro menu to turn it on.")
            }
        }

        /// The input level shown while recording.
        static let level = 0.6
    }

#endif
