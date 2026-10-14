import Testing

@testable import Domain

@Suite("Setting change broadcaster", .timeLimit(.minutes(1)))
struct SettingChangeBroadcasterTests {
    private static let first = SettingChange(name: "general.launchAtLogin")
    private static let second = SettingChange(name: "overlay.edge")

    @Test("a subscriber receives the changes sent after it subscribed, in order")
    func orderedDelivery() async {
        let broadcaster = SettingChangeBroadcaster()
        var iterator = broadcaster.stream().makeAsyncIterator()

        broadcaster.send(Self.first)
        broadcaster.send(Self.second)

        #expect(await iterator.next() == Self.first)
        #expect(await iterator.next() == Self.second)
    }

    @Test("every subscriber gets every change, and one that comes later does not get the earlier ones")
    func independentSubscribers() async {
        let broadcaster = SettingChangeBroadcaster()
        var early = broadcaster.stream().makeAsyncIterator()
        broadcaster.send(Self.first)
        var late = broadcaster.stream().makeAsyncIterator()
        broadcaster.send(Self.second)

        #expect(await early.next() == Self.first)
        #expect(await early.next() == Self.second)
        #expect(await late.next() == Self.second)
    }

    @Test("a change sent while nobody listens is dropped")
    func nobodyListening() async {
        let broadcaster = SettingChangeBroadcaster()
        broadcaster.send(Self.first)
        var iterator = broadcaster.stream().makeAsyncIterator()

        broadcaster.send(Self.second)

        #expect(await iterator.next() == Self.second)
    }

    @Test("a subscriber whose task is cancelled is forgotten")
    func cancelledSubscriberIsRemoved() async {
        let broadcaster = SettingChangeBroadcaster()
        let stream = broadcaster.stream()
        let consumer = Task { for await _ in stream {} }
        let whileSubscribed = broadcaster.subscriberCount

        consumer.cancel()
        await consumer.value

        #expect(whileSubscribed == 1)
        #expect(broadcaster.subscriberCount == 0)
    }
}
