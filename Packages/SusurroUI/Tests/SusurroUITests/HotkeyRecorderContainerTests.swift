import AppKit
import SwiftUI
import Testing
import UITestSupport

@testable import SusurroUI

/// A model that records what the recorder asks of it.
@MainActor
private final class SpyRecorderModel: HotkeyRecorderModeling {
    var state: HotkeyRecorderState
    private(set) var calls: [String] = []

    init(_ state: HotkeyRecorderState) {
        self.state = state
    }

    func begin() { calls.append("begin") }
    func cancel() { calls.append("cancel") }
    func restoreDefault() { calls.append("restoreDefault") }
}

@MainActor
@Suite("Hotkey recorder container", .serialized)
struct HotkeyRecorderContainerTests {
    private let size = CGSize(width: 560, height: 220)

    private func png(of view: some View, scheme: ColorScheme = .light) -> Data {
        SnapshotSupport.pngData(of: view, size: size, scheme: scheme)
    }

    @Test("the container draws the state its model has: the recorder of that state and no other")
    func drawsTheModelsState() {
        let states = [
            SettingsFixtures.recorderIdle, SettingsFixtures.recorderCustom, SettingsFixtures.recorderListening,
            SettingsFixtures.recorderHolding, SettingsFixtures.recorderRefused,
        ]
        for state in states {
            let container = HotkeyRecorderContainer(model: SpyRecorderModel(state))

            #expect(png(of: container) == png(of: HotkeyRecorder(state: state, actions: .none)), "\(state)")
        }
    }

    @Test("a model that has another state is drawn differently")
    func followsTheModel() {
        let model = SpyRecorderModel(SettingsFixtures.recorderIdle)
        let before = png(of: HotkeyRecorderContainer(model: model))

        model.state = SettingsFixtures.recorderListening

        #expect(png(of: HotkeyRecorderContainer(model: model)) != before)
    }

    @Test("every action of the recorder reaches the intent of the model that it names")
    func actionsReachTheModel() {
        let model = SpyRecorderModel(SettingsFixtures.recorderCustom)
        let actions = HotkeyRecorderActions(model: model)

        actions.begin()
        actions.cancel()
        actions.restoreDefault()

        #expect(model.calls == ["begin", "cancel", "restoreDefault"])
    }

    @Test("a recorder that leaves the screen, as it does when another tab is chosen, stops listening")
    func leavingStopsListening() async {
        let model = SpyRecorderModel(SettingsFixtures.recorderListening)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 220), styleMask: [.titled], backing: .buffered,
            defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: HotkeyRecorderContainer(model: model))
        window.orderBack(nil)
        for _ in 0..<50 { await Task.yield() }  // the screen appears
        #expect(model.calls.isEmpty, "a recorder that appears has not been left")

        window.contentView = NSView()
        for _ in 0..<50 { await Task.yield() }  // the screen goes

        #expect(model.calls == ["cancel"])
        window.close()
    }
}
