import CoreTestSupport
import FluidAudio
import Foundation
import Synchronization
import Testing

@testable import FluidAudioASR

@Suite("Vocabulary booster", .timeLimit(.minutes(1)))
struct VocabularyBoosterTests {
    private struct Failure: Error {}

    /// A rescoring session that records what it was asked and answers with a script.
    private final class FakeSession: BoostingSession {
        let terms: [String]
        private let answer: String?
        private let calls = Mutex<[String]>([])

        init(terms: [String], answer: String?) {
            self.terms = terms
            self.answer = answer
        }

        var rescored: [String] { calls.withLock { $0 } }

        func rescore(_ text: String, timings: [TokenTiming], samples: [Float]) async -> String? {
            calls.withLock { $0.append(text) }
            return answer
        }
    }

    /// A loaded model that builds one fake session per call and keeps them in order.
    private final class FakeModel: BoostingModel {
        private let state = Mutex<[FakeSession]>([])
        private let answer: String?
        private let failure: (any Error)?

        init(answer: String? = "rescored", failure: (any Error)? = nil) {
            self.answer = answer
            self.failure = failure
        }

        var sessions: [FakeSession] { state.withLock { $0 } }

        func session(for terms: [String]) async throws -> any BoostingSession {
            if let failure { throw failure }
            let session = FakeSession(terms: terms, answer: answer)
            state.withLock { $0.append(session) }
            return session
        }
    }

    /// Counts the loads, and fails or waits on request.
    private final class Loader: Sendable {
        let model: FakeModel
        let gate = Gate()
        private let gated: Bool
        private let failures: Mutex<Int>
        private let count = Mutex(0)

        init(model: FakeModel = FakeModel(), gated: Bool = false, failures: Int = 0) {
            self.model = model
            self.gated = gated
            self.failures = Mutex(failures)
        }

        var loads: Int { count.withLock { $0 } }

        func load() async throws -> any BoostingModel {
            count.withLock { $0 += 1 }
            if gated { await gate.wait() }
            let fail = failures.withLock { remaining -> Bool in
                defer { remaining = max(0, remaining - 1) }
                return remaining > 0
            }
            if fail { throw Failure() }
            return model
        }
    }

    /// A clock that moves only when a test says so.
    private final class Clock: Sendable {
        private let instant = Mutex(ContinuousClock.now)
        func now() -> ContinuousClock.Instant { instant.withLock { $0 } }
        func advance(by duration: Duration) { instant.withLock { $0 += duration } }
    }

    private static let timings = [
        TokenTiming(token: "▁hola", tokenId: 1, startTime: 0, endTime: 0.4, confidence: 0.9)
    ]
    private static let samples = [Float](repeating: 0.1, count: 16_000)

    private static func booster(
        _ loader: Loader, clock: Clock = Clock(), retryDelay: Duration = .seconds(300)
    ) -> VocabularyBooster {
        VocabularyBooster(load: { try await loader.load() }, retryDelay: retryDelay, now: { clock.now() })
    }

    private static func boost(
        _ text: String = "hola", with booster: VocabularyBooster, terms: [String], timings: [TokenTiming]? = timings,
        samples: [Float] = samples
    ) async -> String {
        await booster.boost(text, timings: timings, samples: samples, terms: terms)
    }

    // MARK: Nothing to do

    @Test("with no terms the text comes back as it is and no model is loaded")
    func noTerms() async {
        let loader = Loader()
        let booster = Self.booster(loader)

        let text = await Self.boost(with: booster, terms: [])

        #expect(text == "hola")
        #expect(loader.loads == 0)
    }

    @Test("terms below five characters are dropped, and with none left no model is loaded")
    func shortTermsAreDropped() async {
        let loader = Loader()
        let booster = Self.booster(loader)

        let text = await Self.boost(with: booster, terms: ["Acme", "Zed", "  ab  ", ""])

        #expect(text == "hola")
        #expect(loader.loads == 0)
    }

    @Test("only the terms of five characters or more reach the session, trimmed")
    func sessionGetsTheLongTerms() async {
        let loader = Loader()
        let booster = Self.booster(loader)
        await booster.prepare()

        _ = await Self.boost(with: booster, terms: ["Acme", " Kaelthorn ", "González"])

        #expect(loader.model.sessions.map(\.terms) == [["Kaelthorn", "González"]])
    }

    @Test(
        "a clip with no token timings, or longer than the limit, is left alone",
        arguments: [
            (timings: [TokenTiming]?.none, seconds: 5), (timings: [TokenTiming]?.some([]), seconds: 5),
            (timings: Self.timings, seconds: 121),
        ]
    )
    func clipsThatCannotBeRescored(timings: [TokenTiming]?, seconds: Int) async {
        let loader = Loader()
        let booster = Self.booster(loader)
        await booster.prepare()

        let text = await Self.boost(
            with: booster, terms: ["Kaelthorn"], timings: timings,
            samples: [Float](repeating: 0.1, count: seconds * 16_000))

        #expect(text == "hola")
        #expect(loader.model.sessions.isEmpty)
    }

    @Test("a clip at the limit is rescored")
    func clipAtTheLimit() async {
        let booster = Self.booster(Loader())
        await booster.prepare()

        let text = await Self.boost(
            with: booster, terms: ["Kaelthorn"], samples: [Float](repeating: 0.1, count: 120 * 16_000))

        #expect(text == "rescored")
    }

    // MARK: Loading

    @Test("the text is left alone while the model loads, and rescored once it is ready")
    func waitsForTheModel() async {
        let loader = Loader(gated: true)
        let booster = Self.booster(loader)

        let early = await Self.boost(with: booster, terms: ["Kaelthorn"])
        let duringLoad = await Self.boost(with: booster, terms: ["Kaelthorn"])
        loader.gate.open()
        await booster.prepare()
        let late = await Self.boost(with: booster, terms: ["Kaelthorn"])

        #expect(early == "hola" && duringLoad == "hola")
        #expect(late == "rescored")
        #expect(loader.loads == 1)
    }

    @Test("a model that loaded stays loaded")
    func loadsOnce() async {
        let loader = Loader()
        let booster = Self.booster(loader)
        await booster.prepare()

        for _ in 0..<3 { _ = await Self.boost(with: booster, terms: ["Kaelthorn"]) }

        #expect(loader.loads == 1)
    }

    @Test("a load that fails leaves the text alone, and is tried again only after the delay")
    func failedLoadWaits() async {
        let loader = Loader(failures: 1)
        let clock = Clock()
        let booster = Self.booster(loader, clock: clock, retryDelay: .seconds(300))

        await booster.prepare()
        let first = await Self.boost(with: booster, terms: ["Kaelthorn"])
        clock.advance(by: .seconds(299))
        let tooSoon = await Self.boost(with: booster, terms: ["Kaelthorn"])
        #expect(loader.loads == 1)

        clock.advance(by: .seconds(2))
        let retry = await Self.boost(with: booster, terms: ["Kaelthorn"])
        await booster.prepare()
        let ready = await Self.boost(with: booster, terms: ["Kaelthorn"])

        #expect([first, tooSoon, retry] == ["hola", "hola", "hola"])
        #expect(loader.loads == 2)
        #expect(ready == "rescored")
    }

    // MARK: Sessions

    @Test("the same terms use one session, whatever their order or case")
    func sameTermsOneSession() async {
        let loader = Loader()
        let booster = Self.booster(loader)
        await booster.prepare()

        _ = await Self.boost(with: booster, terms: ["Kaelthorn", "González"])
        _ = await Self.boost(with: booster, terms: ["González", "Kaelthorn"])
        _ = await Self.boost(with: booster, terms: ["kaelthorn", "gonzález", "Kaelthorn"])

        #expect(loader.model.sessions.count == 1)
        #expect(loader.model.sessions[0].rescored == ["hola", "hola", "hola"])
    }

    @Test("a changed list of terms builds a new session")
    func changedTermsNewSession() async {
        let loader = Loader()
        let booster = Self.booster(loader)
        await booster.prepare()

        _ = await Self.boost(with: booster, terms: ["Kaelthorn"])
        _ = await Self.boost(with: booster, terms: ["Kaelthorn", "González"])
        _ = await Self.boost(with: booster, terms: ["Kaelthorn"])

        #expect(loader.model.sessions.map(\.terms) == [["Kaelthorn"], ["Kaelthorn", "González"], ["Kaelthorn"]])
    }

    @Test("a session that cannot be built leaves the text alone")
    func sessionFailure() async {
        let booster = Self.booster(Loader(model: FakeModel(failure: Failure())))
        await booster.prepare()

        let text = await Self.boost(with: booster, terms: ["Kaelthorn"])

        #expect(text == "hola")
    }

    @Test("a rescoring that changes nothing gives back the text it was given")
    func nothingChanged() async {
        let booster = Self.booster(Loader(model: FakeModel(answer: nil)))
        await booster.prepare()

        let text = await Self.boost("Reunión con Kyle Thorn", with: booster, terms: ["Kaelthorn"])

        #expect(text == "Reunión con Kyle Thorn")
    }
}
