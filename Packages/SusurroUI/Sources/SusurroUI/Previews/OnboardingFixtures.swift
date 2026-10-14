// What the onboarding views show in previews and in snapshot tests, in one place: the previews and the pictures draw
// the same states, so there is one list of them to keep. The words are the ones the app uses.
#if DEBUG

    enum OnboardingFixtures {
        /// The states a row can be in, each with the step that fits it.
        enum Row: CaseIterable, Sendable {
            case granted, notAsked, denied, waitingForPrompt, waitingInSettings, stale, optional
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
    }

#endif
