import SwiftUI

/// Puts the command mode card in front of the code that drives it, with the recorder of the command hotkey in its slot.
/// While the card is on screen it follows the settings, so a switch flipped in the menu shows here.
public struct CommandModeContainer<Recorder: View>: View {
    private let model: any CommandModeSettingsModeling
    private let recorder: Recorder

    public init(model: any CommandModeSettingsModeling, @ViewBuilder recorder: () -> Recorder) {
        self.model = model
        self.recorder = recorder()
    }

    public var body: some View {
        let model = model
        CommandModeSection(model.state, actions: CommandModeActions(model: model)) { recorder }
            .task { await model.follow() }
    }
}
