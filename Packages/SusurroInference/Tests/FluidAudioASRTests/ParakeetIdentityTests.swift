import Domain
import Testing

@testable import FluidAudioASR

@Suite("Parakeet identity")
struct ParakeetIdentityTests {
    @Test("the recognizer names itself, runs locally, and has no clip limit")
    func identity() {
        // Triangulation skipped: these are constants with one possible value.
        let recognizer = ParakeetRecognizer(engine: FakeParakeetEngine())

        #expect(recognizer.id == ASRProviderID("parakeet-v3"))
        #expect(recognizer.locality == .local)
        #expect(recognizer.maxClipDuration == nil)
    }
}
