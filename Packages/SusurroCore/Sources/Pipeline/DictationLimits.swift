/// Limits of the walking skeleton. Later changes replace each one.
public enum DictationLimits {
    /// A shorter hold is discarded.
    public static let minimumHold = Duration.milliseconds(300)
    /// Reaching this much audio finishes the recording.
    public static let recordingCap = Duration.seconds(60)
    /// The pause between readiness checks while the speech model loads.
    public static let readinessPollInterval = Duration.milliseconds(200)
    /// How long a finished recording waits for a loading model whose progress does not change. Any change in progress
    /// starts the count again. The longest plateau measured is the compile for the Neural Engine, about 30 s.
    public static let readinessStallTimeout = Duration.seconds(60)
    /// The most a finished recording waits for a loading model, however it progresses. A first launch downloads and
    /// compiles the model in about a minute on a fast connection.
    public static let readinessHardCap = Duration.seconds(180)
    /// How long asking the recognizer to prepare may take. It only starts a load, so it returns at once.
    public static let prepareTimeout = Duration.seconds(5)
    /// How long the capture may take to start. A device that is slow to open, or a stuck audio system, would otherwise
    /// hold the press at "Getting ready" for good. It is not the stop limit, so that a test can run out one and not the
    /// other.
    public static let captureStartTimeout = Duration.seconds(6)
    /// How long stopping the capture and delivering its last chunks may take.
    public static let captureStopTimeout = Duration.seconds(5)
    public static let transcriptionTimeout = Duration.seconds(30)
    public static let insertionTimeout = Duration.seconds(10)
    /// The most one dictation takes after the key is released: the wait for the model, the transcription, and the
    /// insertion together. It is shorter than the sum of their limits, so a dictation cannot hold the coordinator busy
    /// for all of them in a row, and no shorter than the wait for the model, which a first launch can use up.
    public static let processingCap = Duration.seconds(200)
    /// How long a shutdown waits for the inserter to finish what it has in hand, such as putting the clipboard back.
    /// What is left after that is put back by the app as it terminates.
    public static let drainTimeout = Duration.seconds(2)
}
