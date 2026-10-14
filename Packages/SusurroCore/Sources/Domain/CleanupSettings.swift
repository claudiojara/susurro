/// The settings of the cleanup stage.
public enum CleanupSettings {
    /// Whether the transcript goes through a cleaner at all. Off by default (ADR 0015, addendum): the on-device model adds
    /// seconds to a paste that takes about 0.13 s without it, so cleanup is something the user chooses. A user who stored
    /// `true` while it was on by default keeps it.
    public static let enabled = SettingKey<Bool>(area: "cleanup", name: "enabled", default: false)

    /// The cleaner the user selected, by `CleanerProviderID.rawValue`. A fresh install uses Apple's on-device model.
    public static let provider = SettingKey<String>(
        area: "cleanup", name: "provider", default: CleanerProviderID.appleIntelligence.rawValue)
}
