// The parts of the settings contract for the microphone, the media that plays while dictating, and the shortcut that
// pastes the last dictation. They live apart from `SettingsViewState.swift` so that the tabs grow without crowding it.

/// The microphone and the media cards, at the foot of the General tab.
public nonisolated struct AudioSettingsState: Equatable, Sendable {
    /// The system default first, then each microphone that is connected.
    public let microphones: [SettingsChoice]
    public let selectedMicrophone: String
    /// Why the chosen microphone is not the one in use, or nil when it is.
    public let microphoneNote: String?
    public let pauseMediaEnabled: Bool

    public init(
        microphones: [SettingsChoice], selectedMicrophone: String, microphoneNote: String?, pauseMediaEnabled: Bool
    ) {
        self.microphones = microphones
        self.selectedMicrophone = selectedMicrophone
        self.microphoneNote = microphoneNote
        self.pauseMediaEnabled = pauseMediaEnabled
    }

    /// No microphones listed and nothing on, for a screen that does not offer the cards.
    public static let empty = AudioSettingsState(
        microphones: [], selectedMicrophone: "", microphoneNote: nil, pauseMediaEnabled: false)
}

/// The shortcut that pastes the last dictation, in the Hotkey tab.
public nonisolated struct PasteLastSettingsState: Equatable, Sendable {
    /// The keys of the shortcut, one cap each, or none while it is unassigned.
    public let shortcut: [String]

    public init(shortcut: [String]) {
        self.shortcut = shortcut
    }

    public static let unassigned = PasteLastSettingsState(shortcut: [])
}

public struct AudioActions {
    /// The id of a microphone choice: empty for the system default, or a device's UID.
    public var microphone: (String) -> Void
    public var pauseMedia: (Bool) -> Void

    public static let none = AudioActions(microphone: { _ in }, pauseMedia: { _ in })
}
