/// What a media player answers when it is asked whether it plays. See ADR 0038.
public enum MediaPlayerState: Sendable, Equatable {
    /// The app is not open. Nothing is sent to it, so nothing launches it.
    case notRunning
    case playing
    /// Open, and paused or stopped.
    case notPlaying
    /// Open, but it could not be asked: the user denied the Automation permission, or the app did not answer in time.
    case unavailable
}

/// One media player that the app asks for its state and steers with its own pause and play commands, never with the
/// play/pause key, so media the user had paused is never started. See ADR 0038.
public protocol MediaPlayerControlling: Sendable {
    func state() async -> MediaPlayerState
    /// Pauses the player. It does nothing when the player is not open.
    func pause() async
    /// Plays the player. It does nothing when the player is not open: it never launches it.
    func play() async
}

/// Whether media that plays is paused while the user dictates, stored as `media.pauseWhileDictating`. Off by default, so
/// nothing changes for a user who never turns it on.
public enum MediaSettings {
    public static let pauseWhileDictating = SettingKey<Bool>(
        area: "media", name: "pauseWhileDictating", default: false)

    public static let all: [any AnySettingKey] = [pauseWhileDictating]
}
