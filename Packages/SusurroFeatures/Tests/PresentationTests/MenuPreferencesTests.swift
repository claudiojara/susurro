import CoreTestSupport
import Domain
import Testing

@testable import Presentation

@MainActor
@Suite("Menu preferences", .timeLimit(.minutes(1)))
struct MenuPreferencesTests {
    private let granted: [Permission: PermissionStatus] = [
        .microphone: .granted, .accessibility: .granted, .screenRecording: .granted,
    ]

    private func make(
        settings: InMemorySettingsStore = InMemorySettingsStore()
    ) -> (preferences: MenuPreferences, rig: Rig, settings: InMemorySettingsStore) {
        let rig = Rig(granted)
        let ocr = OCRPreferenceController(settings: settings, monitor: rig.monitor)
        return (MenuPreferences(settings: settings, ocr: ocr), rig, settings)
    }

    @Test("a fresh install leaves cleanup off, uses the app context, and leaves screen text off")
    func defaults() {
        let items = make().preferences.items
        #expect(
            items.map(\.title) == [
                "Clean up text (adds a few seconds)", "Use app context", "Use screen text (OCR)",
            ])
        #expect(items.map(\.isOn) == [false, true, false])
        #expect(items.allSatisfy { $0.note == nil })
    }

    @Test("the cleanup switch writes cleanup.enabled")
    func cleanupSwitch() async {
        let sut = make()
        await sut.preferences.set(.cleanup, to: true)
        #expect(sut.settings.value(for: CleanupSettings.enabled))
        #expect(sut.preferences.items[0].isOn)
        #expect(CleanupSettings.enabled.storageName == "cleanup.enabled")
    }

    @Test("a cleanup switch that an earlier version stored as on is still on")
    func storedCleanupSurvives() {
        let settings = InMemorySettingsStore()
        settings.set(true, for: CleanupSettings.enabled)
        let rig = Rig(granted)
        let preferences = MenuPreferences(
            settings: settings, ocr: OCRPreferenceController(settings: settings, monitor: rig.monitor))
        #expect(preferences.items[0].isOn)
    }

    @Test("the app context switch writes context.useAppContext")
    func appContextSwitch() async {
        let sut = make()
        await sut.preferences.set(.appContext, to: false)
        #expect(!sut.settings.value(for: ContextSettings.useAppContext))
        #expect(sut.preferences.items[1].isOn == false)
        #expect(ContextSettings.useAppContext.storageName == "context.useAppContext")
    }

    @Test("the screen text switch goes through the OCR controller")
    func screenTextSwitch() async {
        let sut = make()
        await sut.preferences.set(.screenText, to: true)
        #expect(sut.settings.value(for: ContextSettings.ocrEnabled))
        #expect(sut.preferences.items[2].isOn)
    }

    @Test("a screen text switch that the system has not allowed carries the reason")
    func screenTextNote() async {
        let rig = Rig([.microphone: .granted, .accessibility: .granted, .screenRecording: .denied])
        let settings = InMemorySettingsStore()
        let preferences = MenuPreferences(
            settings: settings, ocr: OCRPreferenceController(settings: settings, monitor: rig.monitor))
        await preferences.set(.screenText, to: true)
        #expect(preferences.items[2].note?.contains("Screen Recording") == true)
    }

    @Test("the menu model shows the switches and routes a flip to them")
    func menuModelRoutes() async {
        let sut = make()
        let model = MenuModel(monitor: sut.rig.monitor, preferences: sut.preferences)
        #expect(model.content.preferences.map(\.kind) == [.cleanup, .appContext, .screenText])
        await model.setPreference(.cleanup, to: true)
        #expect(model.content.preferences[0].isOn)
    }

    @Test("a menu without preferences shows none")
    func menuWithoutPreferences() {
        let model = MenuModel(monitor: Rig([:]).monitor)
        #expect(model.content.preferences.isEmpty)
    }
}
