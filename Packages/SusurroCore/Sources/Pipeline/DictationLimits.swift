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
    /// How long stopping the capture and delivering its last chunks may take.
    public static let captureStopTimeout = Duration.seconds(5)
    public static let transcriptionTimeout = Duration.seconds(30)
    public static let insertionTimeout = Duration.seconds(10)
}
