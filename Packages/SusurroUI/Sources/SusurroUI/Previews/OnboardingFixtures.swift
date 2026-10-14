// What the onboarding views show in previews and in snapshot tests, in one place: the previews and the pictures draw
// the same states, so there is one list of them to keep. The words are the ones the app uses.
#if DEBUG

    enum OnboardingFixtures {
        /// The states a row can be in, each with the step that fits it.
        enum Row: CaseIterable, Sendable {
            case granted, notAsked, denied, waitingForPrompt, waitingInSettings, stale, optional
        }

        /// The checklists the screens show.
        enum Screen: CaseIterable, Sendable {
            /// A fresh install: nothing is allowed yet.
            case fresh
            case allGranted
            /// The microphone is allowed, and Accessibility is on in System Settings but still not allowed here.
            case stale
            /// Everything the setup can ask for, with the conditional permissions at the end.
            case withOptional
        }

        // The words of the app are in `SusurroFeatures`, which this package cannot read. `OnboardingFixturesTests` there keeps
        // these equal to what the view model builds, so that a change of the words cannot leave them behind.

        /// The banner of a fresh install, and the ones with one required permission missing.
        static let longBanner =
            "Dictation is off until Microphone is allowed. "
            + "Dictated text goes to the clipboard until Accessibility is allowed."
        static let shortBanner = "Dictation is off until Microphone is allowed."
        static let clipboardBanner = "Dictated text goes to the clipboard until Accessibility is allowed."

        static func state(_ screen: Screen) -> OnboardingViewState {
            switch screen {
            case .fresh: screenState(.fresh, banner: longBanner, isDoneEnabled: false)
            case .allGranted: screenState(.allGranted, banner: nil, isDoneEnabled: true)
            case .stale: screenState(.stale, banner: clipboardBanner, isDoneEnabled: false)
            case .withOptional: screenState(.withOptional, banner: nil, isDoneEnabled: true)
            }
        }

        private static func screenState(_ screen: Screen, banner: String?, isDoneEnabled: Bool) -> OnboardingViewState {
            OnboardingViewState(
                title: "Set up Susurro",
                subtitle: "Susurro needs these permissions to hear you and to type what you say.",
                rows: rows(screen), restrictionMessage: banner, recheckTitle: "Check again", doneTitle: "Done",
                isDoneEnabled: isDoneEnabled)
        }

        static func rows(_ screen: Screen) -> [OnboardingRowState] {
            switch screen {
            case .fresh:
                [row(.notAsked), accessibility(status: .denied, text: "Not allowed", action: allow("Accessibility"))]
            case .allGranted: [row(.granted), accessibility(status: .granted, text: "Allowed", action: nil)]
            case .stale: [row(.granted), row(.stale)]
            case .withOptional:
                [
                    row(.granted), accessibility(status: .granted, text: "Allowed", action: nil), inputMonitoring,
                    screenRecording,
                ]
            }
        }

        static func row(_ row: Row) -> OnboardingRowState {
            switch row {
            case .granted: microphone(status: .granted, text: "Allowed", action: nil)
            case .notAsked: microphone(status: .notAsked, text: "Not asked yet", action: allow("Microphone"))
            case .denied: microphone(status: .denied, text: "Not allowed", action: openSettings)
            case .waitingForPrompt: accessibility(status: .waiting, text: "Waiting…", action: nil)
            case .waitingInSettings: accessibility(status: .waiting, text: "Waiting…", action: openSettings)
            case .stale:
                accessibility(status: .stale(guidance: staleGuidance), text: "Needs attention", action: openSettings)
            case .optional: inputMonitoring
            }
        }

        // MARK: Words

        private static let openSettings = OnboardingAction(kind: .openSettings, title: "Open System Settings")

        private static func allow(_ name: String) -> OnboardingAction {
            OnboardingAction(kind: .request, title: "Allow \(name)")
        }

        private static let staleGuidance =
            "Still not allowed? In System Settings, switch Susurro off and on again. If it still does not work, "
            + "remove Susurro from the list, add it again, and switch it on."

        // MARK: Rows

        private static func microphone(status: OnboardingRowStatus, text: String, action: OnboardingAction?)
            -> OnboardingRowState
        {
            OnboardingRowState(
                id: .microphone, title: "Microphone", why: "Needed to hear you while you hold the dictation hotkey.",
                requirement: .required, status: status, statusText: text, action: action)
        }

        private static func accessibility(status: OnboardingRowStatus, text: String, action: OnboardingAction?)
            -> OnboardingRowState
        {
            OnboardingRowState(
                id: .accessibility, title: "Accessibility",
                why: "Needed to paste the dictated text into the app you are using.", requirement: .required,
                status: status, statusText: text, action: action)
        }

        private static let inputMonitoring = OnboardingRowState(
            id: .inputMonitoring, title: "Input Monitoring",
            why: "Needed to notice a hotkey made only of modifier keys, such as fn.",
            requirement: .optional(
                featureNote: "Optional: only for a hotkey made of modifier keys. Dictation works without it."),
            status: .notAsked, statusText: "Not asked yet", action: allow("Input Monitoring"))

        private static let screenRecording = OnboardingRowState(
            id: .screenRecording, title: "Screen Recording",
            why: "Needed to read the text on your screen as context for the cleanup.",
            requirement: .optional(
                featureNote: "Optional: only for reading on-screen text. Dictation works without it."),
            status: .notAsked, statusText: "Not asked yet", action: allow("Screen Recording"))
    }

#endif
