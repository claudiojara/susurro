/// The on-device speech engine of the system behind `AppleSpeechRecognizer`. The live one wraps `SpeechAnalyzer`; tests
/// substitute a fake, so no unit test installs a language or transcribes anything.
protocol AppleSpeechEngine: Sendable {
    /// Whether this Mac can transcribe `language` on the device.
    func isSupported(language: String) async -> Bool
    /// Downloads and installs the language assets if they are not there. `progress` gets fractions in 0...1.
    func install(language: String, progress: @escaping @Sendable (Double) -> Void) async throws
    /// Transcribes 16 kHz mono samples in `language`.
    func transcribe(_ samples: [Float], language: String) async throws -> String
}
