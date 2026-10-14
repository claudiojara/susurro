import AppKit
import CoreTestSupport
import DesignSystem
import Domain
import Pipeline
import Testing

@testable import Presentation

/// The window is AppKit glue: what the history shows is decided by the screen and the view model, which are tested. These
/// tests check the window itself: its kind, and that it opens, comes forward, and closes.
@MainActor
@Suite("History window controller", .timeLimit(.minutes(1)))
struct HistoryWindowControllerTests {
    private final class Activations {
        var count = 0
    }

    private func makeController(activations: Activations = Activations()) -> HistoryWindowController {
        let repository = InMemoryHistoryRepository()
        let model = HistoryViewModel(
            repository: repository,
            actions: HistoryActions(
                repository: repository, deleter: FakeAudioFileDeleter(), clipboard: FakeClipboardWriter()),
            retries: RetryService(
                repository: repository, loader: FakeAudioClipLoader(), reprocessor: FakeDictationReprocessor(text: "x")),
            dates: FakeDateSource())
        return HistoryWindowController(
            model: model, themes: ThemeModel(), activate: { activations.count += 1 },
            frameName: "SusurroHistoryWindowTest-\(UUID().uuidString)")
    }

    @Test("the window is titled and can be closed, resized, and minimized")
    func windowKind() {
        let controller = makeController()

        #expect(controller.window.title == "History")
        #expect(controller.window.styleMask.contains(.titled))
        #expect(controller.window.styleMask.contains(.closable))
        #expect(controller.window.styleMask.contains(.resizable))
        #expect(controller.window.styleMask.contains(.miniaturizable))
        #expect(!controller.window.isReleasedWhenClosed)
    }

    @Test("showing the window brings the app forward and puts the window on the screen, key")
    func showBringsItForward() {
        let activations = Activations()
        let controller = makeController(activations: activations)
        defer { controller.close() }

        controller.show()

        #expect(activations.count == 1)
        #expect(controller.window.isVisible)
    }

    @Test("the window opens at a size that shows a few rows, and no smaller than its smallest")
    func openingSize() {
        let controller = makeController()
        defer { controller.close() }

        controller.show()

        let content = controller.window.contentLayoutRect.size
        #expect(content.width >= controller.window.contentMinSize.width)
        #expect(content.height >= controller.window.contentMinSize.height)
        #expect(content.height > 400)
    }

    @Test("showing it again does not move it, and closing it hides it")
    func showTwice() {
        let controller = makeController()
        controller.show()
        let placed = controller.window.frame

        controller.show()
        #expect(controller.window.frame == placed)

        controller.close()
        #expect(!controller.window.isVisible)
    }
}
