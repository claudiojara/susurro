import CoreTestSupport
import Domain
import SusurroUI
import Testing

@testable import Presentation

@MainActor
@Suite("Settings view model: audio and paste last dictation", .timeLimit(.minutes(1)))
struct AudioSettingsViewModelTests {
    private let builtIn = AudioInputDevice(uid: "builtin", name: "MacBook Pro Microphone")
    private let yeti = AudioInputDevice(uid: "yeti", name: "Yeti")

    @Test("the microphones are the system default first, then each connected one, and the default is chosen")
    func listsMicrophones() async {
        let rig = SettingsRig()
        rig.microphones.set([builtIn, yeti])
        let model = rig.model()
        await model.refresh()

        let audio = model.state.audio
        #expect(audio.microphones.map(\.id) == ["", "builtin", "yeti"])
        #expect(audio.microphones.first?.title == "System default")
        #expect(audio.microphones.last?.title == "Yeti")
        #expect(audio.selectedMicrophone == "")
        #expect(audio.microphoneNote == nil)
    }

    @Test("choosing a microphone stores its UID, and the system default stores nothing")
    func choosesMicrophone() async {
        let rig = SettingsRig()
        rig.microphones.set([builtIn, yeti])
        let model = rig.model()
        await model.refresh()

        model.selectMicrophone("yeti")
        #expect(rig.settings.value(for: MicrophoneSettings.deviceUID) == "yeti")
        #expect(model.state.audio.selectedMicrophone == "yeti")

        model.selectMicrophone("")
        #expect(rig.settings.value(for: MicrophoneSettings.deviceUID) == "")
    }

    @Test("a chosen microphone that is not connected stays chosen, listed as not connected, with a note")
    func missingMicrophone() async {
        let rig = SettingsRig()
        rig.microphones.set([builtIn])
        rig.settings.set("yeti", for: MicrophoneSettings.deviceUID)
        let model = rig.model()
        await model.refresh()

        let audio = model.state.audio
        #expect(audio.selectedMicrophone == "yeti")
        #expect(audio.microphones.map(\.id) == ["", "builtin", "yeti"])
        #expect(audio.microphones.last?.title == "Not connected")
        #expect(audio.microphoneNote != nil)
    }

    @Test("a microphone that connects while the screen is open shows")
    func followsDevices() async {
        let rig = SettingsRig()
        let model = rig.model()
        await model.refresh()
        let running = Task { await model.run() }
        defer { running.cancel() }
        await waitUntil { rig.microphones.listenerCount > 0 }

        rig.microphones.set([yeti])

        await waitUntil { model.state.audio.microphones.map(\.id) == ["", "yeti"] }
        #expect(model.state.audio.microphones.map(\.id) == ["", "yeti"])
    }

    @Test("pause media is off by default, and the switch stores it")
    func pauseMedia() {
        let rig = SettingsRig()
        let model = rig.model()
        #expect(model.state.audio.pauseMediaEnabled == false)

        model.setPauseMedia(true)

        #expect(rig.settings.value(for: MediaSettings.pauseWhileDictating))
        #expect(model.state.audio.pauseMediaEnabled)
    }

    @Test("the paste last dictation shortcut shows its keys, or none while it is unassigned")
    func pasteLastShortcut() {
        let rig = SettingsRig()
        let model = rig.model()
        #expect(model.state.pasteLast == .unassigned)

        rig.settings.set(HotkeyCombo(keyCode: 9, modifiers: [.control, .option]), for: PasteLastSettings.combo)
        model.changed()

        #expect(model.state.pasteLast.shortcut == ["⌃", "⌥", "V"])
    }
}
