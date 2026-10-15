import Domain
import SusurroUI

extension SettingsViewModel {
    /// The microphone card: the system default first, then each connected microphone. A chosen one that is not connected
    /// stays chosen, listed as not connected, so the choice is kept for when it comes back.
    var audioState: AudioSettingsState {
        let chosen = settings.value(for: MicrophoneSettings.deviceUID)
        var choices = [SettingsChoice(id: "", title: SettingsCopy.systemDefaultMicrophone)]
        choices += microphones.map { SettingsChoice(id: $0.uid, title: $0.name) }
        let isMissing = MicrophoneChoice.resolve(preferredUID: chosen, available: microphones) == .missing(uid: chosen)
        if isMissing { choices.append(SettingsChoice(id: chosen, title: SettingsCopy.microphoneNotConnected)) }
        return AudioSettingsState(
            microphones: choices,
            selectedMicrophone: chosen,
            microphoneNote: isMissing ? SettingsCopy.microphoneMissing : nil,
            pauseMediaEnabled: settings.value(for: MediaSettings.pauseWhileDictating))
    }

    var pasteLastState: PasteLastSettingsState {
        PasteLastSettingsState(shortcut: dependencies.pasteLastHotkey())
    }

    /// Stores the microphone by its UID. The system default is stored as nothing, the same as never having chosen.
    public func selectMicrophone(_ id: String) {
        if id.isEmpty {
            settings.remove(MicrophoneSettings.deviceUID)
        } else {
            settings.set(id, for: MicrophoneSettings.deviceUID)
        }
        changed()
    }

    public func setPauseMedia(_ isOn: Bool) {
        settings.set(isOn, for: MediaSettings.pauseWhileDictating)
        changed()
    }

    /// Reads the microphones again each time one connects or goes away, until the task is cancelled.
    func followMicrophones() async {
        for await _ in dependencies.microphones.deviceChanges() {
            microphones = dependencies.microphones.inputDevices()
            changed()
        }
    }
}
