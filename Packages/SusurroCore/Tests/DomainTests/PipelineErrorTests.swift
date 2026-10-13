import Domain
import Testing

@Suite("Pipeline errors")
struct PipelineErrorTests {
    @Test(
        "every error names the way out",
        arguments: [
            (PipelineError.microphoneNotGranted, Remedy.permissions),
            (.recognizerNotInstalled, .settings),
            (.captureFailed, .retry),
            (.recognitionFailed, .retry),
        ]
    )
    func remedy(error: PipelineError, expected: Remedy) {
        #expect(error.remedy == expected)
    }
}
