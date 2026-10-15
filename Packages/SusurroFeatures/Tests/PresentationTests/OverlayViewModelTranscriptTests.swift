import CoreTestSupport
import Domain
import SusurroUI
import Testing

@testable import Presentation

@Suite("Overlay view model: the words while recording", .timeLimit(.minutes(1)))
struct OverlayViewModelTranscriptTests {
    @Test("a partial shows while recording, and the words go away when the recording ends")
    func partialsWhileRecording() async {
        let h = await OverlayHarness()
        await h.model.apply(.recording(.hold))

        await h.model.setTranscript("mañana tengo")
        #expect(await h.model.transcript == "mañana tengo")
        await h.model.setTranscript("mañana tengo una reunión")
        #expect(await h.model.transcript == "mañana tengo una reunión")

        await h.model.apply(.transcribing(progress: nil))
        #expect(await h.model.transcript == "")
    }

    @Test("a partial that arrives when nothing records is not shown, and an empty one clears the words")
    func partialsOutsideARecording() async {
        let h = await OverlayHarness()

        await h.model.setTranscript("late")
        #expect(await h.model.transcript == "")

        await h.model.apply(.recording(.hold))
        await h.model.setTranscript("hola")
        await h.model.setTranscript("")
        #expect(await h.model.transcript == "")
    }

    @Test("the words of a stream of partials reach the model until the stream ends")
    func runPartials() async {
        let h = await OverlayHarness()
        await h.model.apply(.recording(.hold))
        let (partials, continuation) = AsyncStream.makeStream(of: String.self)
        continuation.yield("uno")
        continuation.yield("uno dos")
        continuation.finish()

        await h.model.run(partials: partials)

        #expect(await h.model.transcript == "uno dos")
    }

    @Test("the id that older settings stored for the default style selects the pill")
    func legacyDefaultID() async {
        let h = await OverlayHarness()
        let settings = InMemorySettingsStore()
        settings.set("default", for: OverlaySettings.variant)

        await h.model.read(settings)

        #expect(await h.model.styleID == "pill")
    }
}
