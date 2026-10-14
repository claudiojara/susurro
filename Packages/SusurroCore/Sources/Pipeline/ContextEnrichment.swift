import Domain

/// Reads the text on the screen for the vocabulary, when the user turned OCR on. It is the only door through which
/// screen text enters the pipeline, and it hands the lines to the vocabulary builder and to nothing else: they are not
/// part of the context, of a cleanup request, or of a log.
///
/// OCR is skipped, silently and with no error, when it is off (the default), when the focused field is secure, and when
/// Screen Recording is not granted. A result is dropped when the frontmost app or window changed while it was read, when
/// the dictation was cancelled, and when a newer dictation replaced it.
public struct ContextEnrichment: Sendable {
    private let settings: any SettingsStore
    private let permissions: any PermissionsChecker
    private let recognizer: any ScreenTextRecognizer
    private let frontmost: @Sendable () async -> ScreenTarget?

    /// - Parameter frontmost: The frontmost app and window now, to tell whether they changed during the read. A window
    ///   title it cannot give is nil, and then only the app is compared.
    public init(
        settings: any SettingsStore,
        permissions: any PermissionsChecker,
        recognizer: any ScreenTextRecognizer,
        frontmost: @escaping @Sendable () async -> ScreenTarget?
    ) {
        self.settings = settings
        self.permissions = permissions
        self.recognizer = recognizer
        self.frontmost = frontmost
    }

    /// The lines of text in the window of `target`, or none.
    ///
    /// - Parameters:
    ///   - target: The app, and the window when known, that was frontmost when the dictation began.
    ///   - isSecureField: Whether the focused field is a secure one.
    ///   - isCurrent: Whether the dictation is still the newest one. A superseded dictation drops the result.
    public func screenText(
        for target: ScreenTarget, isSecureField: Bool, isCurrent: @Sendable () async -> Bool = { true }
    ) async -> [String] {
        guard settings.value(for: ContextSettings.ocrEnabled), !isSecureField else { return [] }
        guard await permissions.status(.screenRecording) == .granted else { return [] }
        let lines: [String]
        do {
            lines = try await recognizer.recognize(windowOf: target)
        } catch {
            return []
        }
        guard !Task.isCancelled, await isCurrent(), Self.isSame(target, as: await frontmost()) else { return [] }
        return lines
    }

    /// Whether the frontmost target is still the one the read began in. A window title that is unknown on either side
    /// leaves only the app to compare.
    private static func isSame(_ target: ScreenTarget, as now: ScreenTarget?) -> Bool {
        guard let now, now.app == target.app else { return false }
        guard let before = target.windowTitle, let after = now.windowTitle else { return true }
        return before == after
    }
}
