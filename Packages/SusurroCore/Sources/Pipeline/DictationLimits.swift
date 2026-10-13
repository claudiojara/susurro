/// Limits of the walking skeleton. Later changes replace each one.
public enum DictationLimits {
    /// A shorter hold is discarded.
    public static let minimumHold = Duration.milliseconds(300)
    /// Reaching this much audio finishes the recording.
    public static let recordingCap = Duration.seconds(60)
    /// The pause between readiness checks while the speech model loads.
    public static let readinessPollInterval = Duration.milliseconds(200)
    /// How long a loading model may keep a finished recording waiting.
    public static let readinessTimeout = Duration.seconds(60)
    /// How long stopping the capture and delivering its last chunks may take.
    public static let captureStopTimeout = Duration.seconds(5)
    public static let transcriptionTimeout = Duration.seconds(30)
    public static let insertionTimeout = Duration.seconds(10)
}
