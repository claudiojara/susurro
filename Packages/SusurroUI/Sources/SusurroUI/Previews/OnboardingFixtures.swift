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

        static let shortBanner = "Dictation is off until Accessibility is allowed."
        static let longBanner = "Dictation is off until Microphone and Accessibility are allowed."

        static func rows(_ screen: Screen) -> [OnboardingRowState] {
            switch screen {
            case .fresh: [row(.notAsked), accessibility(status: .denied, action: allow("Accessibility"))]
            case .allGranted: [row(.granted), accessibility(status: .granted, action: nil)]
            case .stale: [row(.granted), row(.stale)]
            case .withOptional:
                [row(.granted), accessibility(status: .granted, action: nil), inputMonitoring, screenRecording]
            }
        }

        static func row(_ row: Row) -> OnboardingRowState {
            switch row {
            case .granted: microphone(status: .granted, action: nil)
            case .notAsked: microphone(status: .notAsked, action: allow("Microphone"))
            case .denied: microphone(status: .denied, action: openSettings)
            case .waitingForPrompt: accessibility(status: .waiting, action: nil)
            case .waitingInSettings: accessibility(status: .waiting, action: openSettings)
            case .stale: accessibility(status: .stale(guidance: staleGuidance), action: openSettings)
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

        private static func microphone(status: OnboardingRowStatus, action: OnboardingAction?) -> OnboardingRowState {
            OnboardingRowState(
                id: .microphone, title: "Microphone", why: "Needed to hear you while you hold the dictation hotkey.",
                requirement: .required, status: status, action: action)
        }

        private static func accessibility(status: OnboardingRowStatus, action: OnboardingAction?) -> OnboardingRowState
        {
            OnboardingRowState(
                id: .accessibility, title: "Accessibility",
                why: "Needed to paste the dictated text into the app you are using.", requirement: .required,
                status: status, action: action)
        }

        private static let inputMonitoring = OnboardingRowState(
            id: .inputMonitoring, title: "Input Monitoring",
            why: "Needed to notice a hotkey made only of modifier keys, such as fn.",
            requirement: .optional(
                featureNote: "Optional: only for a hotkey made of modifier keys. Dictation works without it."),
            status: .notAsked, action: allow("Input Monitoring"))

        private static let screenRecording = OnboardingRowState(
            id: .screenRecording, title: "Screen Recording",
            why: "Needed to read the text on your screen as context for the cleanup.",
            requirement: .optional(
                featureNote: "Optional: only for reading on-screen text. Dictation works without it."),
            status: .notAsked, action: allow("Screen Recording"))
    }

#endif
