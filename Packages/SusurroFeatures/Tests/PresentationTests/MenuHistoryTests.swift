import Testing

@testable import Presentation

@MainActor
@Suite("Menu history item", .timeLimit(.minutes(1)))
struct MenuHistoryTests {
    private final class Opened {
        var count = 0
    }

    @Test("the menu's History item opens the history window, and opening it asks nothing else of the app")
    func openHistory() {
        let opened = Opened()
        let setUps = Opened()
        let model = MenuModel(
            monitor: Rig([:]).monitor, showOnboarding: { setUps.count += 1 }, showHistory: { opened.count += 1 })

        model.openHistory()
        model.openHistory()

        #expect(opened.count == 2)
        #expect(setUps.count == 0)
    }

    @Test("a menu made without a history window can still be asked to open it")
    func noHistoryWindow() {
        MenuModel(monitor: Rig([:]).monitor).openHistory()
    }

    @Test("the Copy Last Dictation item runs the copy it was given, and a menu without one has no such item")
    func copyLastDictation() async {
        let copied = Opened()
        let model = MenuModel(monitor: Rig([:]).monitor, copyLastDictation: { copied.count += 1 })

        #expect(model.canCopyLastDictation)
        await model.copyLastDictation()

        #expect(copied.count == 1)
        #expect(MenuModel(monitor: Rig([:]).monitor).canCopyLastDictation == false)
    }
}
