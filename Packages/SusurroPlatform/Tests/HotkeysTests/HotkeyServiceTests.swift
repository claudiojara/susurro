import CoreTestSupport
import Domain
import Synchronization
import Testing

@testable import Hotkeys

@Suite("Hotkey service", .timeLimit(.minutes(1)))
struct HotkeyServiceTests {
    /// Raw transitions scripted by the test, with a signal for when the service stops listening.
    private final class FakeTransitions: KeyTransitionSource {
        let stoppedListening = Gate()
        private let subscriptionCount = Mutex(0)
        private let stream: AsyncStream<KeyTransition>
        private let continuation: AsyncStream<KeyTransition>.Continuation

        init() {
            (stream, continuation) = AsyncStream.makeStream()
            let stopped = stoppedListening
            continuation.onTermination = { _ in stopped.open() }
        }

        var subscriptions: Int { subscriptionCount.withLock { $0 } }

        func transitions() -> AsyncStream<KeyTransition> {
            subscriptionCount.withLock { $0 += 1 }
            return stream
        }

        func send(_ transition: KeyTransition) { continuation.yield(transition) }
        func finish() { continuation.finish() }
    }

    private final class TestClock: Sendable {
        private let current = Mutex(Duration.zero)
        func set(_ time: Duration) { current.withLock { $0 = time } }
        func now() -> Duration { current.withLock { $0 } }
    }

    @Test("each transition is stamped with the time it is read")
    func stampsTransitions() async {
        let source = FakeTransitions()
        let clock = TestClock()
        let sut = HotkeyService(source: source, now: { clock.now() })
        var events = sut.events().makeAsyncIterator()

        clock.set(.milliseconds(1_000))
        source.send(.down)
        #expect(await events.next() == .down(at: .milliseconds(1_000)))

        clock.set(.milliseconds(1_350))
        source.send(.up)
        #expect(await events.next() == .up(at: .milliseconds(1_350)))
    }

    @Test("repeated downs and a stray up are dropped, and the stream ends when the source does")
    func filtersRepeatsAndEnds() async {
        let source = FakeTransitions()
        let sut = HotkeyService(source: source, now: { .milliseconds(5) })

        for transition in [KeyTransition.up, .down, .down, .up, .up] { source.send(transition) }
        source.finish()

        var seen: [HotkeyEvent] = []
        for await event in sut.events() { seen.append(event) }

        #expect(seen == [.down(at: .milliseconds(5)), .up(at: .milliseconds(5))])
    }

    @Test("the source is released when the consumer stops listening")
    func releasesSourceWhenConsumerStops() async {
        let source = FakeTransitions()
        let sut = HotkeyService(source: source, now: { .zero })

        let reader = Task {
            var events = sut.events().makeAsyncIterator()
            return await events.next()
        }
        source.send(.down)

        #expect(await reader.value == .down(at: .zero))
        await source.stoppedListening.wait()
    }

    @Test("the source is subscribed to as soon as events() is called, whether or not the stream is read")
    func subscribesWhenEventsIsCalled() {
        let source = FakeTransitions()
        let sut = HotkeyService(source: source, now: { .zero })
        #expect(source.subscriptions == 0)

        let events = sut.events()

        #expect(source.subscriptions == 1)
        withExtendedLifetime(events) {}
    }
}
