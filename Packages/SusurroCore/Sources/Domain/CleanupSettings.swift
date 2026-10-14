/// The settings of the cleanup stage.
public enum CleanupSettings {
    /// Whether the transcript goes through a cleaner at all. On by default: cleanup is the point of the app, and the raw
    /// transcript is the fallback whenever it cannot run.
    public static let enabled = SettingKey<Bool>(area: "cleanup", name: "enabled", default: true)

    /// The cleaner the user selected, by `CleanerProviderID.rawValue`. A fresh install uses Apple's on-device model.
    public static let provider = SettingKey<String>(
        area: "cleanup", name: "provider", default: CleanerProviderID.appleIntelligence.rawValue)
}

/// The settings that decide what is read from the app the user is dictating into.
///
/// Provisional: the context-capture track (6b.6) declares `useAppContext` too, under the same storage name and default.
/// Keep one of the two declarations when the tracks are joined.
public enum ContextSettings {
    /// Whether the text around the cursor and the selection are read. On by default.
    public static let useAppContext = SettingKey<Bool>(area: "context", name: "useAppContext", default: true)

    /// Whether the frontmost window is read with OCR to find names for the vocabulary. Off by default, and it also
    /// needs the Screen Recording permission.
    public static let ocrEnabled = SettingKey<Bool>(area: "context", name: "ocrEnabled", default: false)
}
