import DesignSystem
import SwiftUI

/// The cards at the foot of the General tab: the microphone to record from, and whether media that plays is paused while
/// dictating. A pure function of the state and the theme.
struct AudioSection: View {
    @Environment(\.theme) private var theme
    private let state: AudioSettingsState
    private let actions: AudioActions

    init(_ state: AudioSettingsState, actions: AudioActions) {
        self.state = state
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: theme.spacing(.md)) {
            if !state.microphones.isEmpty {
                SettingsCard(Copy.microphone, footer: Copy.microphoneFooter) {
                    ChoiceChips(
                        state.microphones, selected: state.selectedMicrophone, label: Copy.microphone,
                        onSelect: actions.microphone)
                    if let note = state.microphoneNote { TextLabel(note, style: .caption, tint: .warning) }
                }
            }
            SettingsCard(Copy.media) {
                SettingsToggle(
                    Copy.pauseMedia, detail: Copy.pauseMediaDetail, isOn: state.pauseMediaEnabled,
                    onChange: actions.pauseMedia)
            }
        }
    }

    private enum Copy {
        static var microphone: String { L10n.string("audio.microphone", "Microphone") }
        static var microphoneFooter: String {
            L10n.string(
                "audio.microphoneFooter",
                "The microphone Susurro records from. If the one you chose is not connected, the system default is used."
            )
        }
        static var media: String { L10n.string("audio.media", "Media") }
        static var pauseMedia: String { L10n.string("audio.pauseMedia", "Pause media while dictating") }
        static var pauseMediaDetail: String {
            L10n.string(
                "audio.pauseMediaDetail",
                "Pauses Music or Spotify if they are playing when you start, and plays them again when you finish. Other players, such as videos in a browser, are not paused. The first time, macOS asks you to let Susurro control each app."
            )
        }
    }
}

#Preview("AudioSection") { PreviewMatrix { AudioSection.Gallery() } }
