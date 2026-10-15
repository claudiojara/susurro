import CoreTestSupport
import Domain
import Foundation
import Presentation
import Testing

@testable import Composition

@MainActor
@Suite("App environment: paste last dictation and media", .timeLimit(.minutes(1)))
struct AppEnvironmentExtrasTests {
    private static let pressTime = Duration.seconds(100)

    private func history(with records: [DictationRecord]) -> (HistoryDependencies, FakeClipboardWriter) {
        var history = HistoryDependencies.preview()
        let clipboard = FakeClipboardWriter()
        history.repository = InMemoryHistoryRepository(records: records)
        history.clipboard = clipboard
        return (history, clipboard)
    }

    private func succeeded(_ text: String) -> DictationRecord {
        DictationRecord(createdAt: Date(), duration: .seconds(1), status: .succeeded, rawText: text, finalText: text)
    }

    @Test("the paste last dictation shortcut pastes the newest dictation through the inserter")
    func pastesLast() async {
        let (history, _) = history(with: [succeeded("pasted again")])
        let f = AppEnvironmentFixture(history: history)
        f.environment.start()
        await f.eventually("the shortcut to be listened to") { f.pasteLast.listenerCount > 0 }

        f.pasteLast.press()

        await f.eventually("the paste") { f.inserter.insertedTexts == ["pasted again"] }
        #expect(f.inserter.targets == [nil])
        await f.environment.shutdown()
    }

    @Test("the shortcut with an empty history pastes nothing and says so in the overlay")
    func emptyHistory() async {
        let f = AppEnvironmentFixture()
        f.environment.start()
        await f.eventually("the shortcut to be listened to") { f.pasteLast.listenerCount > 0 }

        f.pasteLast.press()

        await f.eventually("the notice") { f.overlay.current == "No dictation to paste yet" }
        #expect(f.inserter.insertedTexts.isEmpty)
        await f.environment.shutdown()
    }

    @Test("the menu copies the last dictation to the clipboard")
    func menuCopies() async {
        let (history, clipboard) = history(with: [succeeded("copied text")])
        let f = AppEnvironmentFixture(history: history)
        f.environment.start()

        #expect(f.environment.menu.canCopyLastDictation)
        await f.environment.menu.copyLastDictation()

        #expect(clipboard.copiedTexts == ["copied text"])
        await f.eventually("the notice") { f.overlay.current == "Last dictation copied to the clipboard" }
        await f.environment.shutdown()
    }

    @Test("with the setting on, media that plays is paused for a dictation and resumed after it")
    func pausesMedia() async {
        let f = AppEnvironmentFixture()
        f.settings.set(true, for: MediaSettings.pauseWhileDictating)
        f.media.playing = true
        f.environment.start()

        f.hotkeys.send(.down(at: Self.pressTime))
        await f.eventually("the media to pause") { f.media.toggles == 1 }
        f.capture.emit(AudioChunk(samples: [Float](repeating: 0.1, count: AudioClip.sampleRate)))
        await f.eventually("the recording indicator") { f.overlay.current == "Listening…" }
        f.hotkeys.send(.up(at: Self.pressTime + .milliseconds(1200)))
        await f.eventually("the media to resume") { f.media.toggles == 2 }

        #expect(f.media.playing)
        await f.environment.shutdown()
    }

    @Test("with the setting off, the media is left alone")
    func mediaOffByDefault() async {
        let f = AppEnvironmentFixture()
        f.media.playing = true
        f.environment.start()

        f.hotkeys.send(.down(at: Self.pressTime))
        f.capture.emit(AudioChunk(samples: [Float](repeating: 0.1, count: AudioClip.sampleRate)))
        await f.eventually("the recording indicator") { f.overlay.current == "Listening…" }
        f.hotkeys.send(.up(at: Self.pressTime + .milliseconds(1200)))
        await f.eventually("the pasted indicator") { f.overlay.current == "Pasted" }

        #expect(f.media.toggles == 0)
        await f.environment.shutdown()
    }
}
