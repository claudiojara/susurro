/// The numbers that bound a recording: how short it may be, how much of it is held in memory, and how closely the file
/// must agree with what was captured.
public enum RecordingLimits {
    /// A recording shorter than this is discarded with no record: an accidental blip.
    public static let minimumDuration = Duration.milliseconds(300)

    /// The most audio a recording holds in memory at any moment, whatever its length. A ten-minute recording is
    /// written out as it is captured, and memory holds only what has not been written yet. The session writes in
    /// batches of `writeBatch`, far below this bound; the bound is the contract that tests hold it to.
    public static let maximumBufferedAudio = Duration.seconds(30)

    /// How much audio the session collects before it writes it out. A buffer of the microphone is about 20 ms, and one
    /// write for each would be many small writes.
    public static let writeBatch = Duration.seconds(1)

    /// How far the length of the file read back may differ from the length of what was captured.
    public static let durationTolerance = Duration.milliseconds(50)
}
