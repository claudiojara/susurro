import SwiftUI

/// Puts the settings screen in front of the code that drives it. It reads the state of its model and sends the steps the
/// user takes to it: the screen below knows neither. The model computes `state` from observable properties, so a change
/// redraws the screen without anything here asking for it. The recorder of the hotkey is a native control from the
/// platform, which the UI package cannot import, so the app passes it in.
public struct SettingsContainer<Recorder: View>: View {
    private let model: any SettingsViewModeling
    private let recorder: Recorder

    public init(model: any SettingsViewModeling, @ViewBuilder recorder: () -> Recorder) {
        self.model = model
        self.recorder = recorder()
    }

    public var body: some View {
        let model = model
        SettingsScreen(state: model.state, actions: SettingsActions(model: model)) { recorder }
            .task { await model.refresh() }
            .task { await model.run() }
    }
}
