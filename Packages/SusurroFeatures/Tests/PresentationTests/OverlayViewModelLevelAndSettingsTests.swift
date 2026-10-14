import CoreTestSupport
import DesignSystem
import Domain
import SusurroUI
import Synchronization
import Testing

@testable import Presentation

/// A time that the test moves.
private final class Uptime: Sendable {
    private let current = Mutex(Duration.zero)
    func advance(by duration: Duration) { current.withLock { $0 += duration } }
    var now: Duration { current.withLock { $0 } }
}

@Suite("Overlay view model: levels, hands-free and settings", .timeLimit(.minutes(1)))
struct OverlayViewModelLevelAndSettingsTests {
    @Test("a hands-free recording shows the flag and how to stop")
    func handsFree() async {
        let h = await OverlayHarness()

        await h.model.apply(.recording(.handsFree))

        let expected = OverlayViewState.recording(
            handsFree: true, text: "Listening…", hint: OverlayMapping.handsFreeHint)
        #expect(await h.model.state == expected)
    }

    @Test("levels reach the meter while recording, no more often than the throttle lets them")
    func levelsAreThrottled() async {
        let uptime = Uptime()
        let h = await OverlayHarness(uptime: { uptime.now })
        await h.model.apply(.recording(.hold))
        var shown: [Double] = []

        for index in 0..<100 {
            await h.model.setLevel(Double(index) / 100)
            let level = await h.model.level
            if shown.last != level { shown.append(level) }
            uptime.advance(by: .milliseconds(1))
        }

        #expect(shown.count <= 3)
        #expect(shown.first == 0)
        #expect(shown.last ?? 0 > 0.3)
    }

    @Test("levels are ignored outside a recording, and the meter goes back to zero when the recording ends")
    func levelsOnlyWhileRecording() async {
        let uptime = Uptime()
        let h = await OverlayHarness(uptime: { uptime.now })

        await h.model.setLevel(0.8)
        #expect(await h.model.level == 0)

        await h.model.apply(.recording(.hold))
        await h.model.setLevel(0.8)
        #expect(await h.model.level == 0.8)

        await h.model.apply(.transcribing(progress: nil))
        #expect(await h.model.level == 0)
        uptime.advance(by: .seconds(1))
        await h.model.setLevel(0.5)
        #expect(await h.model.level == 0)
    }

    @Test("run(levels:) feeds the meter until the stream ends")
    func runConsumesLevels() async {
        let h = await OverlayHarness()
        await h.model.apply(.recording(.hold))
        let (levels, continuation) = AsyncStream.makeStream(of: Double.self)
        continuation.yield(0.7)
        continuation.finish()

        await h.model.run(levels: levels)

        #expect(await h.model.level == 0.7)
    }

    @Test("the style and the edge follow the settings, and the defaults are the pill and the theme's edge")
    func settingsAreFollowed() async {
        let h = await OverlayHarness()
        let settings = InMemorySettingsStore()
        let model = h.model
        let following = Task { await model.follow(settings) }
        while await model.styleID != "pill" { await Task.yield() }

        #expect(await model.edgePreference == nil)

        settings.set("compact", for: OverlaySettings.variant)
        settings.set(OverlayEdgeSetting.top, for: OverlaySettings.edge)
        while await !MainActor.run(body: { model.styleID == "compact" && model.edgePreference == .top }) {
            await Task.yield()
        }

        settings.set(OverlayEdgeSetting.followTheme, for: OverlaySettings.edge)
        while await model.edgePreference != nil { await Task.yield() }
        following.cancel()
    }

    @Test("the user's edge setting reads as an edge, and the theme's setting as none")
    func edgeSettingMapping() async {
        let h = await OverlayHarness()
        let settings = InMemorySettingsStore()

        for (setting, edge): (OverlayEdgeSetting, ScreenEdge?) in [
            (.top, .top), (.bottom, .bottom), (.followTheme, nil),
        ] {
            settings.set(setting, for: OverlaySettings.edge)
            await h.model.read(settings)
            #expect(await h.model.edgePreference == edge)
        }
    }
}
