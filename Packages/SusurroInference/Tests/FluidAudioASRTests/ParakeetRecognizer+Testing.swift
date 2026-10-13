import Domain

@testable import FluidAudioASR

extension ParakeetRecognizer {
    /// A recognizer over `engine` whose model has loaded.
    static func ready(engine: FakeParakeetEngine) async -> ParakeetRecognizer {
        let recognizer = ParakeetRecognizer(engine: engine)
        await recognizer.prepare()
        await recognizer.waitUntilReady()
        return recognizer
    }

    /// Returns once the model is loaded. A load that never finishes ends in the suite's time limit.
    func waitUntilReady() async {
        for await readiness in readinessChanges() where readiness == .ready { return }
    }
}

extension AudioClip {
    /// A clip of `count` samples that differ from one another, so a clip changed on the way is noticed.
    static func ramp(samples count: Int) -> AudioClip {
        AudioClip(samples: (0..<count).map { Float($0 % 100) / 100 })
    }
}
