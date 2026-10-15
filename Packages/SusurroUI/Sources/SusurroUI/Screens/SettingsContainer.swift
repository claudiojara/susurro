import SwiftUI

/// Puts the settings screen in front of the code that drives it. It reads the state of its model and sends the steps the
/// user takes to it: the screen below knows neither. The model computes `state` from observable properties, so a change
/// redraws the screen without anything here asking for it. The recorder of the hotkey (`HotkeyRecorderContainer`) is built
/// by the app over the keys of the platform, which the UI package cannot import, so the app passes it in.
public struct SettingsContainer<Recorder: View>: View {
    private let model: any SettingsViewModeling
    private let recorder: Recorder
    private let pasteLastRecorder: AnyView
    private let hotkeyCards: AnyView

    /// - Parameters:
    ///   - pasteLastRecorder: The recorder of the shortcut that pastes the last dictation, built by the app like
    ///     `recorder`.
    ///   - hotkeyCards: More cards of the Hotkey tab, such as command mode (`CommandModeContainer`).
    public init(
        model: any SettingsViewModeling, pasteLastRecorder: AnyView = AnyView(EmptyView()),
        hotkeyCards: AnyView = AnyView(EmptyView()), @ViewBuilder recorder: () -> Recorder
    ) {
        self.model = model
        self.recorder = recorder()
        self.pasteLastRecorder = pasteLastRecorder
        self.hotkeyCards = hotkeyCards
    }

    public var body: some View {
        let model = model
        SettingsScreen(
            state: model.state, actions: SettingsActions(model: model), pasteLastRecorder: pasteLastRecorder,
            hotkeyCards: hotkeyCards
        ) { recorder }
        .task { await model.refresh() }
        .task { await model.run() }
    }
}
