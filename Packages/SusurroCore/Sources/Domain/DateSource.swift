import Foundation

/// The wall-clock time, for code that stamps or compares dates. It is a port so a test decides what "now" is. Pauses
/// and timers do not use it: they sleep on an injected `Clock`.
public protocol DateSource: Sendable {
    func now() -> Date
}

/// The system's time.
public struct SystemDateSource: DateSource {
    public init() {}

    public func now() -> Date { Date() }
}
