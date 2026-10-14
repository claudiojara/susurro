import Domain
import Foundation
import Synchronization

/// A loader that gives the clip it was set up with for a URL, and fails for one it does not know.
public final class FakeAudioClipLoader: AudioClipLoading {
    public struct Unreadable: Error, Sendable, Equatable {
        public init() {}
    }

    private let clips: Mutex<[URL: AudioClip]>

    public init(clips: [URL: AudioClip] = [:]) {
        self.clips = Mutex(clips)
    }

    public func set(_ clip: AudioClip, at url: URL) {
        clips.withLock { $0[url] = clip }
    }

    public func clip(at url: URL) async throws -> AudioClip {
        guard let clip = clips.withLock({ $0[url] }) else { throw Unreadable() }
        return clip
    }
}
