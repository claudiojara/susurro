import CoreTestSupport
import Domain
import SusurroUI
import Testing

@testable import Presentation

@MainActor
@Suite("Settings view model", .timeLimit(.minutes(1)))
struct SettingsViewModelTests {
    // MARK: Language

    @Test("the language is fast with automatic detection until the user pins one")
    func languageDefault() {
        let state = SettingsRig().model().state.general
        #expect(state.selectedLanguage == "auto")
        #expect(state.languages.map(\.title) == ["Fast (auto language)", "Always Spanish"])
    }

    @Test("pinning Spanish is stored, and the recognizer side reads es from the port")
    func pinnedSpanish() {
        let rig = SettingsRig()
        let model = rig.model()
        model.setLanguage("es")
        #expect(model.state.general.selectedLanguage == "es")
        #expect(SettingsRecognitionLanguage(settings: rig.settings).language() == "es")
        model.setLanguage("auto")
        #expect(SettingsRecognitionLanguage(settings: rig.settings).language() == nil)
    }

    @Test("an unknown language id changes nothing")
    func unknownLanguage() {
        let rig = SettingsRig()
        let model = rig.model()
        model.setLanguage("klingon")
        #expect(model.state.general.selectedLanguage == "auto")
    }

    // MARK: Toggles and overlay

    @Test("app context is on by default, OCR is off, and cleanup is on")
    func toggleDefaults() {
        let general = SettingsRig().model().state.general
        #expect(general.appContextEnabled)
        #expect(!general.ocrEnabled)
        #expect(general.cleanupEnabled)
    }

    @Test("each toggle is written to its own setting")
    func toggles() {
        let rig = SettingsRig()
        let model = rig.model()
        model.setAppContext(false)
        model.setOCR(true)
        model.setCleanup(false)
        #expect(rig.settings.value(for: GeneralSettings.appContextEnabled) == false)
        #expect(rig.settings.value(for: GeneralSettings.ocrEnabled))
        #expect(rig.settings.value(for: CleanupSettings.enabled) == false)
        let general = model.state.general
        #expect(!general.appContextEnabled && general.ocrEnabled && !general.cleanupEnabled)
    }

    @Test("the overlay edge is bottom until the user picks the top")
    func overlayEdge() {
        let rig = SettingsRig()
        let model = rig.model()
        #expect(model.state.general.selectedEdge == "bottom")
        model.setOverlayEdge("top")
        #expect(rig.settings.value(for: GeneralSettings.overlayEdge) == .top)
        model.setOverlayEdge("left")
        #expect(model.state.general.selectedEdge == "top")
    }

    @Test("a known overlay variant is used and a stored unknown one falls back to the default with an error")
    func overlayVariant() {
        let rig = SettingsRig()
        let model = rig.model()
        model.setOverlayVariant("compact")
        #expect(model.state.general.selectedVariant == "compact")
        #expect(model.state.general.variantError == nil)
        model.setOverlayVariant("gone")
        #expect(model.state.general.selectedVariant == OverlayVariantOption.defaultID)
        #expect(model.state.general.variantError?.contains("gone") == true)
        #expect(model.state.general.overlayVariants.map(\.id) == ["default", "compact"])
    }

    @Test("a change made elsewhere, such as a menu toggle, shows while the model runs")
    func followsTheStore() async {
        let rig = SettingsRig()
        let model = rig.model()
        let following = Task { await model.run() }
        defer { following.cancel() }
        for _ in 0..<20 { await Task.yield() }
        rig.settings.set(false, for: CleanupSettings.enabled)
        await waitUntil { !model.state.general.cleanupEnabled }
        #expect(!model.state.general.cleanupEnabled)
    }

    // MARK: Providers

    @Test("a fresh install selects Parakeet v3 and shows its readiness after a refresh")
    func freshProviders() async {
        let rig = SettingsRig()
        let model = rig.model()
        #expect(model.state.speech(ProviderID.parakeetV3)?.isSelected == true)
        #expect(model.state.speech(ProviderID.parakeetV3)?.status.level == .pending)
        await model.refresh()
        let parakeet = model.state.speech(ProviderID.parakeetV3)
        #expect(parakeet?.status == ProviderStatusState(level: .ready, text: "Ready"))
        #expect(model.state.cleanup(ProviderID.appleIntelligence)?.isSelected == true)
    }

    @Test("loading, missing, and failed models show their reason")
    func readinessReasons() async {
        let rig = SettingsRig()
        let model = rig.model()
        rig.knobs.setReadiness(ProviderID.parakeetV3, .loading(progress: 0.4))
        await model.refresh()
        #expect(model.state.speech(ProviderID.parakeetV3)?.status == ProviderStatusState(level: .pending, text: "Loading the model, 40 %."))
        rig.knobs.setReadiness(ProviderID.parakeetV3, .notInstalled)
        await model.refresh()
        #expect(model.state.speech(ProviderID.parakeetV3)?.status.level == .warning)
        rig.knobs.setReadiness(ProviderID.parakeetV3, .unavailable("No disk space.", retryable: false))
        await model.refresh()
        #expect(model.state.speech(ProviderID.parakeetV3)?.status == ProviderStatusState(level: .error, text: "No disk space."))
    }

    @Test("the selected provider is kept across a relaunch")
    func selectionPersists() {
        let rig = SettingsRig()
        rig.model().selectProvider(ProviderID.deepgram)
        let relaunched = rig.model()
        #expect(relaunched.state.speech(ProviderID.deepgram)?.isSelected == true)
        #expect(relaunched.state.speech(ProviderID.parakeetV3)?.isSelected == false)
        relaunched.selectProvider(ProviderID.anthropic)
        #expect(relaunched.state.cleanup(ProviderID.anthropic)?.isSelected == true)
        #expect(relaunched.state.speech(ProviderID.deepgram)?.isSelected == true)
    }

    @Test("an id that is no provider changes nothing")
    func unknownProvider() {
        let rig = SettingsRig()
        let model = rig.model()
        model.selectProvider("nope")
        model.setProviderEnabled("nope", isOn: true)
        model.setProviderField("nope", field: "model", value: "x")
        #expect(rig.settings.value(for: SpeechSettings.provider) == "parakeet-v3")
    }

    @Test("a cloud provider is off, then needs a key, then is ready")
    func cloudProviderSteps() {
        let rig = SettingsRig()
        let model = rig.model()
        var deepgram = model.state.speech(ProviderID.deepgram)
        #expect(deepgram?.isEnabled == false)
        #expect(deepgram?.status.level == .warning)
        #expect(deepgram?.status.text == "Off. Turn it on to use it.")

        model.setProviderEnabled(ProviderID.deepgram, isOn: true)
        deepgram = model.state.speech(ProviderID.deepgram)
        #expect(deepgram?.isEnabled == true)
        #expect(deepgram?.status.text.contains("account deepgram") == false)
        #expect(deepgram?.status.text == "Add a key to your Keychain (app.tuminuta, deepgram).")
        #expect(deepgram?.key?.isPresent == false)

        rig.knobs.setKey(.deepgram, present: true)
        deepgram = model.state.speech(ProviderID.deepgram)
        #expect(deepgram?.status.level == .ready)
        #expect(deepgram?.key?.isPresent == true)
        #expect(rig.settings.value(for: SpeechSettings.deepgramEnabled))
    }

    @Test("the key never reaches the view state, only whether it is there")
    func keyNeverShown() {
        let rig = SettingsRig()
        let model = rig.model()
        rig.knobs.setKey(.anthropic, present: true)
        let dump = String(describing: model.state)
        #expect(model.state.cleanup(ProviderID.anthropic)?.key?.isPresent == true)
        #expect(!dump.contains("sk-"))
    }

    @Test("cleanup providers keep their model and base URL, and a bad base URL is reported")
    func cleanupFields() {
        let rig = SettingsRig()
        let model = rig.model()
        model.setProviderField(ProviderID.anthropic, field: "model", value: "  claude-sonnet-4-5 ")
        model.setProviderField(ProviderID.openAICompatible, field: "model", value: "gpt-4.1-mini")
        model.setProviderField(ProviderID.openAICompatible, field: "baseURL", value: "http://example.com/v1")
        #expect(rig.settings.value(for: CleanupSettings.anthropicModel) == "claude-sonnet-4-5")
        #expect(rig.settings.value(for: CleanupSettings.openAICompatibleModel) == "gpt-4.1-mini")
        let openAI = model.state.cleanup(ProviderID.openAICompatible)
        #expect(openAI?.field("baseURL")?.error == "Use an https address, or http on this Mac.")
        model.setProviderField(ProviderID.openAICompatible, field: "baseURL", value: "http://localhost:11434/v1")
        #expect(model.state.cleanup(ProviderID.openAICompatible)?.field("baseURL")?.error == nil)
        model.setProviderField(ProviderID.openAICompatible, field: "baseURL", value: "https://api.example.com/v1")
        #expect(model.state.cleanup(ProviderID.openAICompatible)?.field("baseURL")?.error == nil)
    }

    @Test("an enabled cleaner with a key and a bad address reports the address, not ready")
    func cleanerWithBadAddress() {
        let rig = SettingsRig()
        let model = rig.model()
        model.setProviderEnabled(ProviderID.openAICompatible, isOn: true)
        model.setProviderField(ProviderID.openAICompatible, field: "baseURL", value: "ftp://x")
        rig.knobs.setKey(.openAICompatible, present: true)
        #expect(model.state.cleanup(ProviderID.openAICompatible)?.status.level == .error)
    }

    @Test("Apple Intelligence reads as unavailable when the Mac does not have it")
    func appleIntelligence() async {
        let rig = SettingsRig()
        let model = rig.model()
        rig.knobs.setAppleIntelligence(false)
        await model.refresh()
        #expect(model.state.cleanup(ProviderID.appleIntelligence)?.status.level == .warning)
    }

    // MARK: Local Whisper

    @Test("the endpoint of Local Whisper must be on this Mac")
    func endpointValidation() {
        let rig = SettingsRig()
        let model = rig.model()
        #expect(model.state.speech(ProviderID.localWhisper)?.field("endpoint")?.error == nil)
        model.setProviderField(ProviderID.localWhisper, field: "endpoint", value: "https://api.example.com/v1/audio")
        let row = model.state.speech(ProviderID.localWhisper)
        #expect(row?.field("endpoint")?.error == "The address must be on this Mac: localhost or 127.0.0.1.")
        #expect(row?.status.level == .error)
        model.setProviderField(ProviderID.localWhisper, field: "endpoint", value: "http://localhost:8080/inference")
        #expect(model.state.speech(ProviderID.localWhisper)?.field("endpoint")?.error == nil)
    }

    @Test("the command line mode shows the path field, validated, and the server mode shows the address")
    func executableValidation() async {
        let rig = SettingsRig()
        let model = rig.model()
        #expect(model.state.speech(ProviderID.localWhisper)?.field("executable") == nil)
        model.setProviderField(ProviderID.localWhisper, field: "mode", value: "cli")
        var row = model.state.speech(ProviderID.localWhisper)
        #expect(row?.field("endpoint") == nil)
        #expect(row?.field("executable")?.error == "Enter the full path of your Whisper command.")
        #expect(row?.status.level == .error)

        rig.knobs.setProblem(nil)
        model.setProviderField(ProviderID.localWhisper, field: "executable", value: "/opt/homebrew/bin/whisper-cli")
        await model.refresh()
        row = model.state.speech(ProviderID.localWhisper)
        #expect(row?.field("executable")?.error == nil)
        #expect(row?.field("executable")?.value == "/opt/homebrew/bin/whisper-cli")
        #expect(row?.status.level == .warning)  // the server or tool does not answer yet
        rig.knobs.setReadiness(ProviderID.localWhisper, .ready)
        await model.refresh()
        #expect(model.state.speech(ProviderID.localWhisper)?.status.level == .ready)
    }

    @Test("the server style and the model are stored")
    func serverStyle() {
        let rig = SettingsRig()
        let model = rig.model()
        model.setProviderField(ProviderID.localWhisper, field: "style", value: "whisperCpp")
        model.setProviderField(ProviderID.localWhisper, field: "model", value: "large-v3")
        #expect(rig.settings.value(for: SpeechSettings.localWhisperServerStyle) == .whisperCpp)
        #expect(rig.settings.value(for: SpeechSettings.localWhisperModel) == "large-v3")
        model.setProviderField(ProviderID.localWhisper, field: "style", value: "bogus")
        #expect(rig.settings.value(for: SpeechSettings.localWhisperServerStyle) == .whisperCpp)
    }

    // MARK: Hotkey

    @Test("a keyed hotkey needs no permission and shows its keys")
    func keyedHotkey() async {
        let rig = SettingsRig()
        let model = rig.model()
        await model.refresh()
        let hotkey = model.state.hotkey
        #expect(hotkey.shortcut == ["⌃", "⌥", "D"])
        #expect(!hotkey.isModifierOnly)
        #expect(hotkey.permissionWarning == nil)
    }

    @Test("a modifier-only hotkey without Input Monitoring reports the missing permission and offers a request")
    func modifierOnlyWithoutPermission() async {
        let rig = SettingsRig()
        rig.knobs.setHotkey(HotkeyDescription(keys: ["fn"], isModifierOnly: true))
        let model = rig.model()
        await model.refresh()
        let warning = model.state.hotkey.permissionWarning
        #expect(warning?.message.contains("Input Monitoring") == true)
        #expect(warning?.actionTitle == "Allow Input Monitoring")

        await model.requestInputMonitoring()
        #expect(rig.permissions.requested == [.inputMonitoring])
        #expect(model.state.hotkey.permissionWarning != nil)  // the user has not answered yet

        rig.permissions.set(.inputMonitoring, to: .granted)
        await model.refresh()
        #expect(model.state.hotkey.permissionWarning == nil)
    }

    @Test("Secure Event Input shows a warning while it is on")
    func secureInput() async {
        let rig = SettingsRig()
        let model = rig.model()
        await model.refresh()
        #expect(model.state.hotkey.secureInputWarning == nil)
        rig.knobs.setSecureInput(true)
        await model.refresh()
        #expect(model.state.hotkey.secureInputWarning?.contains("Secure Event Input") == true)
        rig.knobs.setSecureInput(false)
        await model.refresh()
        #expect(model.state.hotkey.secureInputWarning == nil)
    }
}
