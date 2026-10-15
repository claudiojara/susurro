import Domain
import Foundation

/// A media player steered through its own scripting commands (ADR 0038): it is asked for its `player state`, and told to
/// `pause` and `play`, never sent the play/pause key, which toggles whatever app the system treats as playing and so
/// could start music the user had paused. Every event goes to the running process by its process identifier, which
/// never launches the app, and an app that is not open gets nothing at all.
///
/// The first event to each app asks the user for the Automation permission. A denied permission, or an app that does
/// not answer in time, reads as `unavailable`, so that player is skipped.
public struct ScriptedMediaPlayer: MediaPlayerControlling {
    /// The players the app knows, with the codes of their scripting dictionaries (`sdef`). Both use the same
    /// `player state` property and enumeration.
    public struct App: Sendable, Equatable {
        public let bundleIdentifier: String
        /// The suite of the `pause` and `play` commands: `hook` for Music, `spfy` for Spotify.
        let suite: FourCharCode

        public static let music = App(bundleIdentifier: "com.apple.Music", suite: FourCharCode(fourCharacters: "hook"))
        public static let spotify = App(
            bundleIdentifier: "com.spotify.client", suite: FourCharCode(fourCharacters: "spfy"))
        public static let all: [App] = [.music, .spotify]
    }

    private static let playerState = FourCharCode(fourCharacters: "pPlS")
    private static let playing = FourCharCode(fourCharacters: "kPSP")
    private static let paused = FourCharCode(fourCharacters: "kPSp")
    private static let stopped = FourCharCode(fourCharacters: "kPSS")

    private let app: App
    private let events: any AppleEventSending

    public init(_ app: App, events: any AppleEventSending = LiveAppleEvents()) {
        self.app = app
        self.events = events
    }

    public func state() async -> MediaPlayerState {
        guard let process = events.processIdentifier(of: app.bundleIdentifier) else { return .notRunning }
        guard let state = try? await events.send(.getProperty(Self.playerState), to: process) else {
            return .unavailable
        }
        switch state {
        case Self.playing: return .playing
        case Self.paused, Self.stopped: return .notPlaying
        default: return .unavailable
        }
    }

    public func pause() async {
        await command(FourCharCode(fourCharacters: "Paus"))
    }

    public func play() async {
        await command(FourCharCode(fourCharacters: "Play"))
    }

    private func command(_ id: FourCharCode) async {
        guard let process = events.processIdentifier(of: app.bundleIdentifier) else { return }
        _ = try? await events.send(.command(suite: app.suite, id: id), to: process)
    }
}

/// An Apple Event the media players are sent.
public enum AppleEventRequest: Sendable, Equatable {
    /// `get` of a property of the application, answered with an enumeration code.
    case getProperty(FourCharCode)
    /// A command with no parameters.
    case command(suite: FourCharCode, id: FourCharCode)
}

/// An Apple Event that failed, with its OSStatus: -1743 is a denied Automation permission, -1712 a timeout, -600 an app
/// that quit.
public struct AppleEventFailure: Error, Equatable {
    public let code: Int

    public init(code: Int) {
        self.code = code
    }
}

/// Sends Apple Events to running apps. The live one is `LiveAppleEvents`; the tests fake it.
public protocol AppleEventSending: Sendable {
    /// The process of the running app with that bundle identifier, or nil when it is not open.
    func processIdentifier(of bundleIdentifier: String) -> Int32?
    /// Sends the event to that process and returns the reply's enumeration code, if it has one.
    func send(_ request: AppleEventRequest, to process: Int32) async throws(AppleEventFailure) -> FourCharCode?
}

extension FourCharCode {
    /// The code of four ASCII characters, as the scripting dictionaries write it.
    public init(fourCharacters: String) {
        self = fourCharacters.utf8.prefix(4).reduce(0) { ($0 << 8) | FourCharCode($1) }
    }
}
