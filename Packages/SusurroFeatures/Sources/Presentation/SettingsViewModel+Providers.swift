import Domain
import SusurroUI

extension SettingsViewModel {
    var providersState: ProvidersSettingsState {
        ProvidersSettingsState(speech: speechRows, cleanup: cleanupRows)
    }

    // MARK: Speech

    private var speechRows: [ProviderRowState] {
        let selected = settings.value(for: SpeechSettings.provider)
        return [
            parakeetRow(selected: selected == ProviderID.parakeetV3),
            localWhisperRow(selected: selected == ProviderID.localWhisper),
            cloudRow(
                id: ProviderID.deepgram, title: "Deepgram", account: .deepgram, what: "audio",
                isSelected: selected == ProviderID.deepgram,
                isEnabled: settings.value(for: SpeechSettings.deepgramEnabled),
                fields: []),
        ]
    }

    private func parakeetRow(selected: Bool) -> ProviderRowState {
        ProviderRowState(
            id: ProviderID.parakeetV3, title: "Parakeet v3", locality: SettingsCopy.thisMac, isCloud: false,
            isSelected: selected, status: Self.status(of: readiness[ProviderID.parakeetV3]), isEnabled: nil, key: nil,
            fields: [])
    }

    private func localWhisperRow(selected: Bool) -> ProviderRowState {
        let mode = settings.value(for: SpeechSettings.localWhisperMode)
        let endpoint = settings.value(for: SpeechSettings.localWhisperEndpoint)
        let executable = settings.value(for: SpeechSettings.localWhisperExecutable)
        let endpointError = LoopbackEndpoint.validated(endpoint) == nil ? SettingsCopy.localWhisperAddressError : nil
        let executableError = dependencies.executableProblem(executable).map(SettingsCopy.executableProblem)

        var fields = [
            ProviderFieldState(
                id: "mode", label: "Connection", value: mode.rawValue,
                choices: [
                    SettingsChoice(id: LocalWhisperMode.http.rawValue, title: "Server on this Mac"),
                    SettingsChoice(id: LocalWhisperMode.cli.rawValue, title: "Command line tool"),
                ])
        ]
        switch mode {
        case .http:
            fields.append(
                ProviderFieldState(
                    id: "style", label: "Server",
                    value: settings.value(for: SpeechSettings.localWhisperServerStyle).rawValue,
                    choices: [
                        SettingsChoice(
                            id: LocalWhisperServerStyle.openAICompatible.rawValue, title: "OpenAI-compatible"),
                        SettingsChoice(id: LocalWhisperServerStyle.whisperCpp.rawValue, title: "whisper.cpp server"),
                    ]))
            fields.append(
                ProviderFieldState(
                    id: "endpoint", label: "Address", value: endpoint,
                    placeholder: "http://127.0.0.1:8080/v1/audio/transcriptions", error: endpointError))
            fields.append(
                ProviderFieldState(
                    id: "model", label: "Model (optional)",
                    value: settings.value(for: SpeechSettings.localWhisperModel),
                    placeholder: "whisper-1"))
        case .cli:
            fields.append(
                ProviderFieldState(
                    id: "executable", label: "Command path", value: executable,
                    placeholder: "/opt/homebrew/bin/whisper-cli", error: executableError))
        }

        let configurationError = mode == .http ? endpointError : executableError
        let status =
            configurationError.map { ProviderStatusState(level: .error, text: $0) }
            ?? Self.status(of: readiness[ProviderID.localWhisper], notInstalled: SettingsCopy.notReachable)
        return ProviderRowState(
            id: ProviderID.localWhisper, title: "Local Whisper", locality: SettingsCopy.thisMac, isCloud: false,
            isSelected: selected, status: status, isEnabled: nil, key: nil, fields: fields)
    }

    /// The status a local speech provider shows for the readiness it reported, or that it has not reported yet.
    private static func status(
        of readiness: RecognizerReadiness?, notInstalled: String = SettingsCopy.modelNotInstalled
    ) -> ProviderStatusState {
        switch readiness {
        case nil: ProviderStatusState(level: .pending, text: SettingsCopy.checking)
        case .ready: ProviderStatusState(level: .ready, text: SettingsCopy.ready)
        case .loading(let progress): ProviderStatusState(level: .pending, text: SettingsCopy.loading(progress))
        case .notInstalled: ProviderStatusState(level: .warning, text: notInstalled)
        case .unavailable(let reason, _): ProviderStatusState(level: .error, text: reason)
        }
    }

    // MARK: Cleanup

    private var cleanupRows: [ProviderRowState] {
        let selected = settings.value(for: CleanupSettings.provider)
        let openAIURL = settings.value(for: CleanupSettings.openAICompatibleBaseURL)
        return [
            appleIntelligenceRow(selected: selected == ProviderID.appleIntelligence),
            cloudRow(
                id: ProviderID.anthropic, title: "Anthropic", account: .anthropic, what: "transcript",
                isSelected: selected == ProviderID.anthropic,
                isEnabled: settings.value(for: CleanupSettings.anthropicEnabled),
                fields: [
                    ProviderFieldState(
                        id: "model", label: "Model", value: settings.value(for: CleanupSettings.anthropicModel),
                        placeholder: "claude-haiku-4-5")
                ]),
            cloudRow(
                id: ProviderID.openAICompatible, title: "OpenAI-compatible", account: .openAICompatible,
                what: "transcript", isSelected: selected == ProviderID.openAICompatible,
                isEnabled: settings.value(for: CleanupSettings.openAICompatibleEnabled),
                fields: [
                    ProviderFieldState(
                        id: "baseURL", label: "Base URL", value: openAIURL, placeholder: "https://api.openai.com/v1",
                        error: CloudEndpoint.validated(openAIURL) == nil ? SettingsCopy.baseURLError : nil),
                    ProviderFieldState(
                        id: "model", label: "Model", value: settings.value(for: CleanupSettings.openAICompatibleModel),
                        placeholder: "gpt-4o-mini"),
                ]),
        ]
    }

    private func appleIntelligenceRow(selected: Bool) -> ProviderRowState {
        let status =
            switch appleIntelligenceAvailable {
            case nil: ProviderStatusState(level: .pending, text: SettingsCopy.checking)
            case true?: ProviderStatusState(level: .ready, text: SettingsCopy.ready)
            case false?: ProviderStatusState(level: .warning, text: SettingsCopy.appleUnavailable)
            }
        return ProviderRowState(
            id: ProviderID.appleIntelligence, title: "Apple Intelligence", locality: SettingsCopy.thisMac,
            isCloud: false, isSelected: selected, status: status, isEnabled: nil, key: nil, fields: [])
    }

    // MARK: Cloud providers

    /// A cloud provider is usable only when it is on and has a key. Whether the key exists is all that is asked.
    private func cloudRow(
        id: String, title: String, account: SecretAccount, what: String, isSelected: Bool, isEnabled: Bool,
        fields: [ProviderFieldState]
    ) -> ProviderRowState {
        let hasKey = dependencies.hasKey(account)
        let fieldError = fields.first { $0.error != nil }?.error
        let status: ProviderStatusState
        if !isEnabled {
            status = ProviderStatusState(level: .warning, text: SettingsCopy.off)
        } else if !hasKey {
            status = ProviderStatusState(level: .warning, text: SettingsCopy.needsKey(account))
        } else if let fieldError {
            status = ProviderStatusState(level: .error, text: fieldError)
        } else {
            status = ProviderStatusState(level: .ready, text: SettingsCopy.sentTo(title, what: what))
        }
        return ProviderRowState(
            id: id, title: title, locality: SettingsCopy.cloud, isCloud: true, isSelected: isSelected, status: status,
            isEnabled: isEnabled,
            key: ProviderKeyState(
                isPresent: hasKey, note: hasKey ? SettingsCopy.keyPresent(account) : SettingsCopy.keyMissing(account)),
            fields: fields)
    }

    // MARK: Intents

    public func selectProvider(_ id: String) {
        switch id {
        case ProviderID.parakeetV3, ProviderID.localWhisper, ProviderID.deepgram:
            settings.set(id, for: SpeechSettings.provider)
        case ProviderID.appleIntelligence, ProviderID.anthropic, ProviderID.openAICompatible:
            settings.set(id, for: CleanupSettings.provider)
        default:
            return
        }
        changed()
    }

    public func setProviderEnabled(_ id: String, isOn: Bool) {
        switch id {
        case ProviderID.deepgram: settings.set(isOn, for: SpeechSettings.deepgramEnabled)
        case ProviderID.anthropic: settings.set(isOn, for: CleanupSettings.anthropicEnabled)
        case ProviderID.openAICompatible: settings.set(isOn, for: CleanupSettings.openAICompatibleEnabled)
        default: return
        }
        changed()
    }

    public func setProviderField(_ id: String, field: String, value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (id, field) {
        case (ProviderID.localWhisper, "mode"):
            guard let mode = LocalWhisperMode(rawValue: trimmed) else { return }
            settings.set(mode, for: SpeechSettings.localWhisperMode)
        case (ProviderID.localWhisper, "style"):
            guard let style = LocalWhisperServerStyle(rawValue: trimmed) else { return }
            settings.set(style, for: SpeechSettings.localWhisperServerStyle)
        case (ProviderID.localWhisper, "endpoint"): settings.set(trimmed, for: SpeechSettings.localWhisperEndpoint)
        case (ProviderID.localWhisper, "model"): settings.set(trimmed, for: SpeechSettings.localWhisperModel)
        case (ProviderID.localWhisper, "executable"): settings.set(trimmed, for: SpeechSettings.localWhisperExecutable)
        case (ProviderID.anthropic, "model"): settings.set(trimmed, for: CleanupSettings.anthropicModel)
        case (ProviderID.openAICompatible, "baseURL"):
            settings.set(trimmed, for: CleanupSettings.openAICompatibleBaseURL)
        case (ProviderID.openAICompatible, "model"): settings.set(trimmed, for: CleanupSettings.openAICompatibleModel)
        default: return
        }
        changed()
    }
}
