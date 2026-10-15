/// The media that plays on this Mac, as far as the app can tell and steer it without private frameworks. See ADR 0031.
public protocol MediaPlaybackControlling: Sendable {
    /// Whether another app is playing sound now.
    func isPlaying() async -> Bool
    /// Sends the play/pause media key, which the system hands to the app that plays media now.
    func togglePlayPause() async
}

/// Whether media that plays is paused while the user dictates, stored as `media.pauseWhileDictating`. Off by default, so
/// nothing changes for a user who never turns it on.
public enum MediaSettings {
    public static let pauseWhileDictating = SettingKey<Bool>(
        area: "media", name: "pauseWhileDictating", default: false)

    public static let all: [any AnySettingKey] = [pauseWhileDictating]
}
