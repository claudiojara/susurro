import Domain

@testable import FluidAudioASR

extension ParakeetRecognizer {
    /// Returns once the model is loaded. A load that never finishes ends in the suite's time limit.
    func waitUntilReady() async {
        for await readiness in readinessChanges() where readiness == .ready { return }
    }
}
