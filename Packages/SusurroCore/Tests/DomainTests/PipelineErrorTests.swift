import Domain
import Testing

@Suite("Pipeline errors")
struct PipelineErrorTests {
    @Test("every error names the way out")
    func remedies() {
        #expect(PipelineError.microphoneNotGranted.remedy == .permissions)
        #expect(PipelineError.recognizerNotInstalled.remedy == .settings)
        #expect(PipelineError.recognizerUnavailable("offline", retryable: true).remedy == .retry)
        #expect(PipelineError.recognizerUnavailable("model is damaged", retryable: false).remedy == .settings)
        #expect(PipelineError.captureFailed("device").remedy == .retry)
        #expect(PipelineError.persistenceFailed("disk").remedy == .retry)
        #expect(PipelineError.timedOut(.capture).remedy == .retry)
        // The recording is kept, so the way out is the history.
        #expect(PipelineError.recognitionFailed("model").remedy == .history)
        #expect(PipelineError.timedOut(.transcription).remedy == .history)
        #expect(PipelineError.timedOut(.readiness).remedy == .history)
        #expect(PipelineError.timedOut(.insertion).remedy == .history)
        #expect(PipelineError.notInserted(.clipboardChanged).remedy == .history)
        #expect(PipelineError.notInserted(.clipboardWriteFailed).remedy == .history)
    }

    @Test("every error has a kind that names the case and leaves out the text it carries")
    func kinds() {
        let secret = "text the user said"
        let kinds: [(PipelineError, String)] = [
            (.microphoneNotGranted, "microphoneNotGranted"),
            (.recognizerNotInstalled, "recognizerNotInstalled"),
            (.recognizerUnavailable(secret, retryable: true), "recognizerUnavailable"),
            (.captureFailed(secret), "captureFailed"),
            (.recognitionFailed(secret), "recognitionFailed"),
            (.timedOut(.readiness), "timedOut.readiness"),
            (.timedOut(.capture), "timedOut.capture"),
            (.timedOut(.transcription), "timedOut.transcription"),
            (.timedOut(.insertion), "timedOut.insertion"),
            (.notInserted(.clipboardChanged), "notInserted.clipboardChanged"),
            (.notInserted(.clipboardWriteFailed), "notInserted.clipboardWriteFailed"),
            (.persistenceFailed(secret), "persistenceFailed"),
        ]
        for (error, kind) in kinds {
            #expect(error.kind == kind)
        }
    }
}
