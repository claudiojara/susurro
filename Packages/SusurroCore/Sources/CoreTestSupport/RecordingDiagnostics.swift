import Domain
import Synchronization

/// A log that keeps the events it is given, in order.
public final class RecordingDiagnostics: DiagnosticsLog {
    private let recorded = Mutex<[DiagnosticEvent]>([])

    public init() {}

    public var events: [DiagnosticEvent] { recorded.withLock { $0 } }

    public func record(_ event: DiagnosticEvent) {
        recorded.withLock { $0.append(event) }
    }
}
