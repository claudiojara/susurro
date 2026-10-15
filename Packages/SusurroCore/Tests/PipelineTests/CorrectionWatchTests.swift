import CoreTestSupport
import Domain
import Foundation
import Testing
import TextShaping

@testable import Pipeline

@Suite("Correction watch", .timeLimit(.minutes(1)))
struct CorrectionWatchTests {
    static let inserted = "I spoke with Kyle Thorn about the launch."
    static let corrected = "Hello team. I spoke with Kaelthorn about the launch. See you."
    static let unchanged = "Hello team. I spoke with Kyle Thorn about the launch. See you."

    struct Fixture {
        let settings = InMemorySettingsStore()
        let reader = FakeFocusedContextReader()
        let clock = ManualClock()
        let diagnostics = RecordingDiagnostics()
        let dates = FakeDateSource()
        let frontmost: FakeFrontmostAppProvider
        let watch: CorrectionWatch
        var store: SuggestionStore { SuggestionStore(settings: settings) }

        init(tagger: FakeEntityTagger = FakeEntityTagger()) async {
            let frontmost = await MainActor.run { FakeFrontmostAppProvider(.mail) }
            self.frontmost = frontmost
            let settings = settings
            let clock = clock
            watch = CorrectionWatch(
                reader: reader, frontmost: frontmost, store: SuggestionStore(settings: settings),
                dictionaryTerms: { settings.value(for: DictionarySettings.terms) },
                filter: SuggestionFilter(tagger: tagger), settings: settings, dates: dates, diagnostics: diagnostics,
                sleep: { try await clock.sleep(for: $0) })
        }

        static func receipt(
            app: AppIdentity = .mail, category: AppCategory = .email, isSecureField: Bool = false,
            inserted: String = CorrectionWatchTests.inserted
        ) -> InsertionReceipt {
            InsertionReceipt(
                id: UUID(), finalText: inserted, anchorBefore: "Hello team. ", anchorAfter: " See you.", target: app,
                category: category, isSecureField: isSecureField)
        }

        static func field(_ text: String, isSecure: Bool = false) -> FocusedContext {
            FocusedContext(isSecure: isSecure, fieldText: text, selection: text.utf16.count..<text.utf16.count)
        }

        /// Watches the receipt and lets the 5 s reread run.
        func watchAndReread(_ receipt: InsertionReceipt = receipt()) async {
            let sleeps = clock.suspendedSleeps
            await watch.watch(receipt)
            if await watch.isWatching { await clock.waitForSleeps(sleeps + 1) }
            clock.advance(by: CorrectionWatch.rereadDelay)
            await watch.settled()
        }

        var terms: [String] { store.suggestions().map(\.term) }
        var ends: [CorrectionWatchEnd] {
            diagnostics.events.compactMap {
                if case .correctionWatchEnded(let reason) = $0 { reason } else { nil }
            }
        }
    }

    // MARK: Timing

    @Test("the field is read again 5 s after the paste, not before, and a correction there is suggested")
    func rereadAfterFiveSeconds() async {
        let f = await Fixture()
        f.reader.set(Fixture.field(Self.corrected))

        await f.watch.watch(Fixture.receipt())
        await f.clock.waitForSleeps(1)
        f.clock.advance(by: .seconds(4))
        #expect(f.reader.reads == 0)
        f.clock.advance(by: .seconds(1))
        await f.watch.settled()

        #expect(f.reader.reads == 1)
        #expect(
            f.store.suggestions() == [
                DictionarySuggestion(term: "Kaelthorn", heard: "Kyle Thorn", firstSeen: f.dates.now())
            ])
        #expect(f.ends == [.suggested])
    }

    @Test("the watch stops at the first match: the next dictation's context is not diffed again")
    func stopsAtFirstMatch() async {
        let f = await Fixture()
        f.reader.set(Fixture.field(Self.corrected))
        await f.watchAndReread()

        await f.watch.handoff(DictationContext(app: .mail, beforeCursor: Self.corrected))

        #expect(f.store.suggestions().map(\.count) == [1])
        #expect(f.ends == [.suggested])
    }

    @Test("a reread with no correction yet keeps the dictation for the next dictation's context")
    func handoff() async {
        let f = await Fixture()
        f.reader.set(Fixture.field(Self.unchanged))
        await f.watchAndReread()
        #expect(f.terms.isEmpty)
        #expect(f.ends.isEmpty)

        await f.watch.handoff(
            DictationContext(
                app: .mail, beforeCursor: "Hello team. I spoke with Kaelthorn about the launch.",
                afterCursor: " See you."))

        #expect(f.terms == ["Kaelthorn"])
        #expect(f.ends == [.suggested])
        #expect(await !f.watch.isWatching)
    }

    @Test("the next dictation's context hands in a correction before the 5 s reread, which then never runs")
    func handoffBeforeReread() async {
        let f = await Fixture()
        await f.watch.watch(Fixture.receipt())
        await f.clock.waitForSleeps(1)

        await f.watch.handoff(DictationContext(app: .mail, beforeCursor: Self.corrected))
        f.clock.advance(by: CorrectionWatch.rereadDelay)
        await f.watch.settled()

        #expect(f.terms == ["Kaelthorn"])
        #expect(f.reader.reads == 0)
    }

    @Test("a newer insertion replaces the older one, which is never read")
    func newerCancelsOlder() async {
        let f = await Fixture()
        f.reader.set(Fixture.field(Self.corrected))
        await f.watch.watch(Fixture.receipt(inserted: "something else entirely"))
        await f.clock.waitForSleeps(1)

        await f.watchAndReread()

        #expect(f.reader.reads == 1)
        #expect(f.ends == [.replaced, .suggested])
        #expect(f.terms == ["Kaelthorn"])
    }

    @Test("with another app in front at 5 s nothing is read, and a handoff from that app ends the watch")
    func appSwitched() async {
        let f = await Fixture()
        f.reader.set(Fixture.field(Self.corrected))
        await MainActor.run { f.frontmost.app = .slack }
        await f.watchAndReread()
        #expect(f.reader.reads == 0)

        await f.watch.handoff(DictationContext(app: .slack, beforeCursor: Self.corrected))

        #expect(f.terms.isEmpty)
        #expect(f.ends == [.appSwitched])
    }

    @Test("a dictation seen corrected twice counts twice")
    func counts() async {
        let f = await Fixture()
        f.reader.set(Fixture.field(Self.corrected))
        await f.watchAndReread()
        await f.watchAndReread()

        #expect(f.store.suggestions().map(\.count) == [2])
    }

    @Test("a dismissed term, or one in the dictionary already, is not suggested")
    func dismissedAndKnown() async {
        let f = await Fixture()
        f.reader.set(Fixture.field(Self.corrected))
        f.store.dismiss("kaelthorn")
        await f.watchAndReread()
        #expect(f.terms.isEmpty)

        f.settings.set([], for: DictionarySettings.dismissed)
        f.settings.set(["Kaelthorn"], for: DictionarySettings.terms)
        await f.watchAndReread()

        #expect(f.terms.isEmpty)
    }

    @Test("the anchors gone at 5 s keep the watch; gone in the handoff too, it ends without a suggestion")
    func anchorLost() async {
        let f = await Fixture()
        f.reader.set(Fixture.field(""))
        await f.watchAndReread()
        #expect(f.ends.isEmpty)

        await f.watch.handoff(DictationContext(app: .mail, beforeCursor: "a new message"))

        #expect(f.ends == [.anchorLost])
    }

    // MARK: When nothing is watched

    @Test(
        "nothing is watched when learning is off, app context is off, the field is secure, or the app is a terminal",
        arguments: ["learn", "context", "secure", "terminal"])
    func skipped(reason: String) async {
        let f = await Fixture()
        f.reader.set(Fixture.field(Self.corrected))
        var receipt = Fixture.receipt()
        switch reason {
        case "learn": f.settings.set(false, for: DictionarySettings.learnFromCorrections)
        case "context": f.settings.set(false, for: ContextSettings.useAppContext)
        case "secure": receipt = Fixture.receipt(isSecureField: true)
        default: receipt = Fixture.receipt(category: .terminal)
        }

        await f.watchAndReread(receipt)
        await f.watch.handoff(DictationContext(app: .mail, beforeCursor: Self.corrected))

        #expect(f.reader.reads == 0)
        #expect(f.terms.isEmpty)
        #expect(await !f.watch.isWatching)
    }

    @Test("a field that reads as secure at 5 s is not diffed")
    func secureOnReread() async {
        let f = await Fixture()
        f.reader.set(Fixture.field(Self.corrected, isSecure: true))
        await f.watchAndReread()

        #expect(f.terms.isEmpty)
    }

    // MARK: Privacy

    @Test("the text of the field is never stored in the settings nor logged: only the corrected word is kept")
    func privacy() async {
        let tagger = FakeEntityTagger()
        let f = await Fixture(tagger: tagger)
        let field = "SENTINEL_FIELD_HEAD " + Self.corrected + " SENTINEL_FIELD_TAIL"
        f.reader.set(Fixture.field(field))
        await f.watchAndReread()
        await f.watch.handoff(DictationContext(app: .mail, beforeCursor: field))

        #expect(f.terms == ["Kaelthorn"])
        #expect(!f.settings.dump.contains("SENTINEL"))
        #expect(!f.settings.dump.contains("Hello team"))
        #expect(!String(describing: f.diagnostics.events).contains("SENTINEL"))
        #expect(!String(describing: f.diagnostics.events).contains("Kaelthorn"))
    }
}
