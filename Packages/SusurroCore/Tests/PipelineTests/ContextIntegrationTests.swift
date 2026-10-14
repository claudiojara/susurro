import CoreTestSupport
import Domain
import Foundation
import Pipeline
import Synchronization
import Testing
import TextShaping

/// Collects what the pipeline hands to `onResolved`, as a consumer of the context would.
private final class Resolutions: Sendable {
    private let items = Mutex<[ResolvedContext]>([])
    var all: [ResolvedContext] { items.withLock { $0 } }
    func add(_ resolved: ResolvedContext) { items.withLock { $0.append(resolved) } }
}

@Suite("Coordinator context integration", .timeLimit(.minutes(1)))
struct ContextIntegrationTests {
    private static let sentinels = [
        "SENTINEL_BEFORE_TEXT", "SENTINEL_AFTER_TEXT", "SENTINEL_SELECTION_TEXT", "SENTINEL_WINDOW_TITLE",
        "SENTINEL_URL_PATH",
    ]

    /// A context full of text that must never be kept.
    private static func sensitiveContext(app: AppIdentity, url: String? = nil) -> DictationContext {
        DictationContext(
            app: app, windowTitle: "SENTINEL_WINDOW_TITLE", url: url, beforeCursor: "SENTINEL_BEFORE_TEXT",
            afterCursor: "SENTINEL_AFTER_TEXT", selection: "SENTINEL_SELECTION_TEXT")
    }

    private struct Fixture {
        let resolutions = Resolutions()
        let source: FakeContextSource
        let frontmost: FakeFrontmostAppProvider
        let sleeper = FakeSleeper(blocksPauses: true)  // the 300 ms deadline fires only when a test fires it
        let diagnostics = RecordingDiagnostics()
        var harness: CoordinatorHarness

        init(source: FakeContextSource, app: AppIdentity? = .mail, styleSettings: StyleSettings = .default) async {
            self.source = source
            frontmost = await MainActor.run { FakeFrontmostAppProvider(app) }
            let resolutions = resolutions
            let pipeline = ContextPipeline(
                source: source, styleSettings: { _, _ in styleSettings }, onResolved: { resolutions.add($0) })
            harness = await CoordinatorHarness(
                sleeper: sleeper, frontmost: frontmost, context: pipeline, diagnostics: diagnostics)
        }

        /// Presses, records, releases after a hold long enough to be kept, and reads the rest of the cycle.
        mutating func dictate() async -> [PipelineState] {
            await harness.startRecording()
            return await harness.release()
        }
    }

    // MARK: Asynchronous capture (6c.1)

    @Test("a context that takes seconds never delays the recording, and the dictation goes on with an empty one")
    func slowContext() async {
        var f = await Fixture(source: FakeContextSource(context: nil, gated: true))
        await f.harness.sut.handle(.down(at: DictationCoordinatorTests.pressTime))
        f.harness.capture.emit(AudioChunk(samples: DictationCoordinatorTests.clip))
        // The recording started while the context is still being captured.
        let started = await f.harness.read(through: .recording(.hold))
        await f.source.entered(call: 0).wait()
        #expect(started.last == .recording(.hold))
        #expect(f.source.callCount == 1)

        await f.harness.sut.handle(.up(at: DictationCoordinatorTests.pressTime + .milliseconds(1200)))
        await f.sleeper.entered(DictationLimits.contextDeadline).wait()
        f.sleeper.fire(DictationLimits.contextDeadline)  // 300 ms after the stop, the context is given up on
        let rest = await f.harness.read(through: .idle)

        #expect(rest == [.transcribing(progress: nil), .inserted, .idle])
        #expect(f.harness.inserter.insertedTexts == ["hello"])
        #expect(f.resolutions.all.map(\.context) == [.empty(app: .mail)])
        #expect(f.resolutions.all.map(\.style) == [StyleProfile(category: .email, tone: .formal, source: .bundle)])
        f.source.release(call: 0)
    }

    @Test("a context that arrives in time is the one the style is chosen from")
    func contextInTime() async {
        let context = DictationContext(
            app: .slack, windowTitle: "general", beforeCursor: "see you", afterCursor: "", selection: "")
        var f = await Fixture(source: FakeContextSource(context: context), app: .slack)

        _ = await f.dictate()

        #expect(f.resolutions.all.map(\.context) == [context])
        #expect(f.resolutions.all.map(\.style) == [StyleProfile(category: .workChat, tone: .casual, source: .bundle)])
        #expect(f.source.apps == [.slack])
    }

    @Test("a snapshot that arrives after the dictation was cancelled is dropped")
    func cancelledDictation() async {
        var f = await Fixture(source: FakeContextSource(context: nil, gated: true))
        await f.harness.sut.handle(.down(at: DictationCoordinatorTests.pressTime))
        f.harness.capture.emit(AudioChunk(samples: DictationCoordinatorTests.clip))
        _ = await f.harness.read(through: .recording(.hold))
        await f.source.entered(call: 0).wait()

        // A hold shorter than the minimum is discarded: the dictation is over.
        await f.harness.sut.handle(.up(at: DictationCoordinatorTests.pressTime + .milliseconds(100)))
        _ = await f.harness.read(through: .idle)
        f.source.release(call: 0)
        await f.source.finished(call: 0).wait()

        #expect(f.resolutions.all.isEmpty)
        #expect(f.diagnostics.events.isEmpty)
    }

    @Test("a snapshot that arrives after a newer dictation began is dropped, and the newer one keeps its own")
    func supersededDictation() async {
        let first = DictationContext(app: .mail, beforeCursor: "FIRST")
        let second = DictationContext(app: .mail, beforeCursor: "SECOND")
        let source = FakeContextSource(steps: [
            .init(context: first, gated: true), .init(context: second),
        ])
        var f = await Fixture(source: source)

        // The first dictation is cancelled while its context is still being captured.
        await f.harness.sut.handle(.down(at: DictationCoordinatorTests.pressTime))
        f.harness.capture.emit(AudioChunk(samples: DictationCoordinatorTests.clip))
        _ = await f.harness.read(through: .recording(.hold))
        await f.source.entered(call: 0).wait()
        await f.harness.sut.handle(.up(at: DictationCoordinatorTests.pressTime + .milliseconds(100)))
        _ = await f.harness.read(through: .idle)

        // A second dictation runs through, and then the first context finally arrives.
        _ = await f.dictate()
        f.source.release(call: 0)
        await f.source.finished(call: 0).wait()

        #expect(f.resolutions.all.map(\.context) == [second])
    }

    @Test("with no context pipeline nothing is captured and the dictation is unchanged")
    func noPipeline() async {
        var h = await CoordinatorHarness()
        await h.startRecording()

        let states = await h.release()

        #expect(states == [.transcribing(progress: nil), .inserted, .idle])
    }

    // MARK: Style

    @Test("the style follows the page in a browser, and the user's settings")
    func styleFromThePage() async {
        let safari = AppIdentity(processID: 7, name: "Safari", bundleID: "com.apple.Safari")
        let context = DictationContext(app: safari, url: "https://claude.ai/new")
        let settings = StyleSettings(tones: [.aiChat: .casual])
        var f = await Fixture(source: FakeContextSource(context: context), app: safari, styleSettings: settings)

        _ = await f.dictate()

        #expect(f.resolutions.all.map(\.style) == [StyleProfile(category: .aiChat, tone: .casual, source: .url)])
    }

    @Test("the style that was chosen is logged by name, per dictation")
    func styleIsLogged() async {
        var f = await Fixture(source: FakeContextSource(context: nil), app: .slack)

        _ = await f.dictate()

        #expect(
            f.diagnostics.events.contains(.styleResolved(category: "work_chat", tone: "casual", source: "bundle")))
    }

    // MARK: Privacy (6c.2)

    @Test("the record holds the app, the host of the page, and the style, and nothing else")
    func recordFields() {
        let safari = AppIdentity(processID: 7, name: "Safari", bundleID: "com.apple.Safari")
        let context = Self.sensitiveContext(app: safari, url: "https://mail.google.com/SENTINEL_URL_PATH?q=1")
        let style = StyleProfile(category: .email, tone: .formal, source: .url)

        let blank = DictationRecord(createdAt: Date(timeIntervalSince1970: 0), duration: .seconds(1))

        let record = ResolvedContext(context: context, style: style).stamped(blank)

        var expected = blank
        expected.bundleID = "com.apple.Safari"
        expected.appName = "Safari"
        expected.urlHost = "mail.google.com"
        expected.category = "email"
        expected.tone = "formal"
        expected.styleSource = "url"
        #expect(record == expected)
        let stored = String(describing: record)
        for sentinel in Self.sentinels { #expect(!stored.contains(sentinel)) }
    }

    @Test("the persisted record and the log of a dictation hold none of its text")
    func nothingLeaks() async throws {
        let context = Self.sensitiveContext(
            app: .mail, url: nil)
        var f = await Fixture(source: FakeContextSource(context: context))

        _ = await f.dictate()

        let resolved = try #require(f.resolutions.all.first)
        let json = String(
            describing: resolved.stamped(DictationRecord(createdAt: Date(timeIntervalSince1970: 0), duration: .zero)))
        let logged = String(describing: f.diagnostics.events)
        for sentinel in Self.sentinels {
            #expect(!json.contains(sentinel))
            #expect(!logged.contains(sentinel))
        }
        #expect(json.contains("com.apple.mail"))
        #expect(!logged.isEmpty)
    }

    @Test("the context of a dictation is not Codable, so it cannot be stored by accident")
    func contextIsNotCodable() {
        #expect(!(DictationContext.self is any Encodable.Type))
        #expect(!(ResolvedContext.self is any Encodable.Type))
    }
}
