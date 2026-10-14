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
    private let frontmost: @Sendable () async -> AppIdentity?

    /// - Parameter frontmost: The frontmost app and window now, to tell whether they changed during the read.
    public init(
        settings: any SettingsStore,
        permissions: any PermissionsChecker,
        recognizer: any ScreenTextRecognizer,
        frontmost: @escaping @Sendable () async -> AppIdentity?
    ) {
        self.settings = settings
        self.permissions = permissions
        self.recognizer = recognizer
        self.frontmost = frontmost
    }

    /// The lines of text in the window of `app`, or none.
    ///
    /// - Parameters:
    ///   - app: The app that was frontmost when the dictation began.
    ///   - isSecureField: Whether the focused field is a secure one.
    ///   - isCurrent: Whether the dictation is still the newest one. A superseded dictation drops the result.
    public func screenText(
        for app: AppIdentity, isSecureField: Bool, isCurrent: @Sendable () async -> Bool = { true }
    ) async -> [String] {
        guard settings.value(for: ContextSettings.ocrEnabled), !isSecureField else { return [] }
        guard await permissions.status(.screenRecording) == .granted else { return [] }
        let lines: [String]
        do {
            lines = try await recognizer.recognize(windowOf: app)
        } catch {
            return []
        }
        guard !Task.isCancelled, await isCurrent(), await frontmost() == app else { return [] }
        return lines
    }
}
