// What the settings views show in previews and in snapshot tests, in one place: the previews and the pictures draw the
// same states, so there is one list of them to keep. The words are the ones the app uses.
#if DEBUG

    enum SettingsFixtures {
        // MARK: Choices

        static let languages = [
            SettingsChoice(id: "auto", title: "Fast (auto language)"),
            SettingsChoice(id: "es", title: "Always Spanish"),
        ]
        static let edges = [SettingsChoice(id: "top", title: "Top"), SettingsChoice(id: "bottom", title: "Bottom")]
        static let variants = [
            SettingsChoice(id: "default", title: "Default"), SettingsChoice(id: "compact", title: "Compact"),
        ]
        static let tones = [
            SettingsChoice(id: "formal", title: "Formal"), SettingsChoice(id: "neutral", title: "Neutral"),
            SettingsChoice(id: "casual", title: "Casual"), SettingsChoice(id: "veryCasual", title: "Very casual"),
            SettingsChoice(id: "verbatim", title: "Verbatim"),
        ]
        static let categories = [
            SettingsChoice(id: "email", title: "Email"), SettingsChoice(id: "work_chat", title: "Work chat"),
            SettingsChoice(id: "personal_messaging", title: "Personal messaging"),
            SettingsChoice(id: "document", title: "Document"), SettingsChoice(id: "terminal", title: "Terminal"),
            SettingsChoice(id: "ai_chat", title: "AI chat"), SettingsChoice(id: "other", title: "Other"),
        ]

        // MARK: General

        static let general = GeneralSettingsState(
            languages: languages, selectedLanguage: "auto", appContextEnabled: true, ocrEnabled: false,
            cleanupEnabled: true, overlayEdges: edges, selectedEdge: "bottom", overlayVariants: variants,
            selectedVariant: "default", variantError: nil)

        static let generalPinned = GeneralSettingsState(
            languages: languages, selectedLanguage: "es", appContextEnabled: false, ocrEnabled: true,
            cleanupEnabled: false, overlayEdges: edges, selectedEdge: "top", overlayVariants: variants,
            selectedVariant: "default",
            variantError: "The overlay style \"gone\" is not available, so the default one is used.")

        // MARK: Providers

        enum Row: CaseIterable, Sendable {
            case parakeetReady, parakeetLoading, localWhisperServer, localWhisperInvalid, deepgramOff, deepgramNeedsKey
            case deepgramReady, anthropicReady, openAICompatible
        }

        static func row(_ row: Row) -> ProviderRowState {
            switch row {
            case .parakeetReady: parakeet(status: ProviderStatusState(level: .ready, text: "Ready"), selected: true)
            case .parakeetLoading:
                parakeet(
                    status: ProviderStatusState(level: .pending, text: "Loading the model, 40 %."), selected: false)
            case .localWhisperServer: localWhisper(address: "http://127.0.0.1:8080/inference", error: nil)
            case .localWhisperInvalid:
                localWhisper(
                    address: "https://api.example.com/v1",
                    error: "The address must be on this Mac: localhost or 127.0.0.1.")
            case .deepgramOff:
                cloud(
                    id: "deepgram", title: "Deepgram", isEnabled: false, hasKey: false,
                    status: ProviderStatusState(level: .warning, text: "Off. Turn it on to use it."), selected: false,
                    fields: [])
            case .deepgramNeedsKey:
                cloud(
                    id: "deepgram", title: "Deepgram", isEnabled: true, hasKey: false,
                    status: ProviderStatusState(
                        level: .warning, text: "Add a key to your Keychain (app.tuminuta, deepgram)."),
                    selected: true, fields: [])
            case .deepgramReady:
                cloud(
                    id: "deepgram", title: "Deepgram", isEnabled: true, hasKey: true,
                    status: ProviderStatusState(level: .ready, text: "Ready. The audio is sent to Deepgram."),
                    selected: true, fields: [])
            case .anthropicReady:
                cloud(
                    id: "anthropic", title: "Anthropic", isEnabled: true, hasKey: true,
                    status: ProviderStatusState(level: .ready, text: "Ready. The transcript is sent to Anthropic."),
                    selected: false,
                    fields: [ProviderFieldState(id: "model", label: "Model", value: "claude-haiku-4-5")])
            case .openAICompatible:
                cloud(
                    id: "openai-compatible", title: "OpenAI-compatible", isEnabled: true, hasKey: true,
                    status: ProviderStatusState(level: .error, text: "Use an https address, or http on this Mac."),
                    selected: false,
                    fields: [
                        ProviderFieldState(
                            id: "baseURL", label: "Base URL", value: "http://example.com/v1",
                            error: "Use an https address, or http on this Mac."),
                        ProviderFieldState(id: "model", label: "Model", value: "gpt-4o-mini"),
                    ])
            }
        }

        static let providers = ProvidersSettingsState(
            speech: [row(.parakeetReady), row(.localWhisperServer), row(.deepgramOff)],
            cleanup: [
                ProviderRowState(
                    id: "apple-intelligence", title: "Apple Intelligence", locality: "On this Mac", isCloud: false,
                    isSelected: true, status: ProviderStatusState(level: .ready, text: "Ready"), isEnabled: nil,
                    key: nil, fields: []),
                row(.anthropicReady),
            ])

        private static func parakeet(status: ProviderStatusState, selected: Bool) -> ProviderRowState {
            ProviderRowState(
                id: "parakeet-v3", title: "Parakeet v3", locality: "On this Mac", isCloud: false, isSelected: selected,
                status: status, isEnabled: nil, key: nil, fields: [])
        }

        private static func localWhisper(address: String, error: String?) -> ProviderRowState {
            ProviderRowState(
                id: "local-whisper", title: "Local Whisper", locality: "On this Mac", isCloud: false, isSelected: false,
                status: error.map { ProviderStatusState(level: .error, text: $0) }
                    ?? ProviderStatusState(level: .ready, text: "Ready"),
                isEnabled: nil, key: nil,
                fields: [
                    ProviderFieldState(
                        id: "mode", label: "Connection", value: "http",
                        choices: [
                            SettingsChoice(id: "http", title: "Server on this Mac"),
                            SettingsChoice(id: "cli", title: "Command line tool"),
                        ]),
                    ProviderFieldState(
                        id: "style", label: "Server", value: "openAICompatible",
                        choices: [
                            SettingsChoice(id: "openAICompatible", title: "OpenAI-compatible"),
                            SettingsChoice(id: "whisperCpp", title: "whisper.cpp server"),
                        ]),
                    ProviderFieldState(id: "endpoint", label: "Address", value: address, error: error),
                    ProviderFieldState(id: "model", label: "Model (optional)", value: "", placeholder: "whisper-1"),
                ])
        }

        private static func cloud(
            id: String, title: String, isEnabled: Bool, hasKey: Bool, status: ProviderStatusState, selected: Bool,
            fields: [ProviderFieldState]
        ) -> ProviderRowState {
            ProviderRowState(
                id: id, title: title, locality: "Cloud service", isCloud: true, isSelected: selected, status: status,
                isEnabled: isEnabled,
                key: ProviderKeyState(
                    isPresent: hasKey,
                    note: hasKey
                        ? "A key is in your Keychain (app.tuminuta, \(id))."
                        : "Add the key to your Keychain: service app.tuminuta, account \(id)."),
                fields: fields)
        }

        // MARK: Hotkey

        static let hotkey = HotkeySettingsState(
            shortcut: ["⌃", "⌥", "D"], isModifierOnly: false, permissionWarning: nil, secureInputWarning: nil)

        static let hotkeyWarnings = HotkeySettingsState(
            shortcut: ["fn"], isModifierOnly: true,
            permissionWarning: HotkeyWarning(
                message:
                    "This hotkey is made only of modifier keys, so it stays off until Input Monitoring is allowed.",
                actionTitle: "Allow Input Monitoring"),
            secureInputWarning:
                "Secure Event Input is on, so keyed shortcuts may not respond until it ends. A password field or another app has turned it on."
        )

        // MARK: Style

        static let style = StyleSettingsState(
            rows: [
                StyleRowState(id: "email", title: "Email", toneID: "formal", isEdited: false),
                StyleRowState(id: "work_chat", title: "Work chat", toneID: "casual", isEdited: false),
                StyleRowState(
                    id: "personal_messaging", title: "Personal messaging", toneID: "veryCasual", isEdited: false),
                StyleRowState(id: "document", title: "Document", toneID: "neutral", isEdited: false),
                StyleRowState(id: "terminal", title: "Terminal", toneID: "verbatim", isEdited: false),
                StyleRowState(id: "ai_chat", title: "AI chat", toneID: "neutral", isEdited: false),
                StyleRowState(id: "other", title: "Other", toneID: "neutral", isEdited: false),
            ],
            toneChoices: tones, categoryChoices: categories, overrides: [], overrideError: nil)

        static let styleWithOverrides = StyleSettingsState(
            rows: style.rows.map {
                $0.id == "email"
                    ? StyleRowState(id: $0.id, title: $0.title, toneID: "casual", isEdited: true) : $0
            },
            toneChoices: tones, categoryChoices: categories,
            overrides: [
                StyleOverrideRowState(
                    id: "app:com.apple.Notes", kind: "App", identifier: "com.apple.Notes", summary: "Tone: Casual"),
                StyleOverrideRowState(
                    id: "site:docs.google.com", kind: "Site", identifier: "docs.google.com",
                    summary: "Category: Document, Tone: Formal"),
            ],
            overrideError: "Choose a category, a tone, or both.")

        // MARK: Dictionary and appearance

        static let dictionaryEmpty = DictionarySettingsState(terms: [], error: nil)
        static let dictionary = DictionarySettingsState(
            terms: ["Acme", "Maria Gonzalez", "kubectl"], error: "That term is already in the dictionary.")

        static let appearance = AppearanceSettingsState(
            themes: [SettingsChoice(id: "default", title: "Default"), SettingsChoice(id: "ocean", title: "ocean")],
            selectedTheme: "default",
            modes: [
                SettingsChoice(id: "system", title: "Follow the system"), SettingsChoice(id: "light", title: "Light"),
                SettingsChoice(id: "dark", title: "Dark"),
            ],
            selectedMode: "system", themeError: nil)

        // MARK: Screen

        static let screen = SettingsViewState(
            general: general, providers: providers, hotkey: hotkey, style: style, dictionary: dictionary,
            appearance: appearance)
    }

#endif
