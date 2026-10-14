import Domain

/// How long the overlay holds an indicator that dismisses itself. An error stays longer than a success, since it asks
/// the user to do something.
struct OverlayTiming: Equatable, Sendable {
    var inserted: Duration
    var notice: Duration
    var error: Duration

    static let standard = OverlayTiming(inserted: .milliseconds(1_200), notice: .seconds(3), error: .seconds(6))

    /// How long the indicator for `state` is held, or nil for a state that stays until the pipeline moves on.
    func dwell(for state: PipelineState) -> Duration? {
        switch state {
        case .inserted: inserted
        case .notice: notice
        case .error: error
        case .idle, .starting, .recording, .transcribing, .polishing: nil
        }
    }
}
