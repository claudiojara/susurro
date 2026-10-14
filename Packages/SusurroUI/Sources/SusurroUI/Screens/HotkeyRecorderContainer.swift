import SwiftUI

/// Puts the recorder of the hotkey in front of the code that drives it. It reads the state of its model and sends the
/// steps the user takes to it: the recorder below knows neither. A recorder that leaves the screen, because the user chose
/// another tab or closed the window, stops listening, so that it never goes on hearing keys that nobody sees.
public struct HotkeyRecorderContainer: View {
    private let model: any HotkeyRecorderModeling

    public init(model: any HotkeyRecorderModeling) {
        self.model = model
    }

    public var body: some View {
        let model = model
        HotkeyRecorder(state: model.state, actions: HotkeyRecorderActions(model: model))
            .onDisappear { model.cancel() }
    }
}
