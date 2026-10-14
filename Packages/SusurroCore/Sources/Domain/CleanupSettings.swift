/// The settings of the cleanup stage.
public enum CleanupSettings {
    /// Whether the transcript goes through a cleaner at all. On by default: cleanup is the point of the app, and the raw
    /// transcript is the fallback whenever it cannot run.
    public static let enabled = SettingKey<Bool>(area: "cleanup", name: "enabled", default: true)

    /// The cleaner the user selected, by `CleanerProviderID.rawValue`. A fresh install uses Apple's on-device model.
    public static let provider = SettingKey<String>(
        area: "cleanup", name: "provider", default: CleanerProviderID.appleIntelligence.rawValue)
}
