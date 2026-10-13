import Domain
import Testing

@Suite("Pipeline errors")
struct PipelineErrorTests {
    @Test("every error names the way out")
    func remedies() {
        #expect(PipelineError.microphoneNotGranted.remedy == .permissions)
        #expect(PipelineError.recognizerNotInstalled.remedy == .settings)
        #expect(PipelineError.captureFailed.remedy == .retry)
        #expect(PipelineError.recognitionFailed.remedy == .retry)
        #expect(PipelineError.timedOut(.transcription).remedy == .retry)
    }
}
