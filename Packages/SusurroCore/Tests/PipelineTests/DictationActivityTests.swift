import CoreTestSupport
import Domain
import Pipeline
import Testing

@Suite("Dictation activity", .timeLimit(.minutes(1)))
struct DictationActivityTests {
    private typealias Harness = CoordinatorHarness
    private static let pressTime = DictationCoordinatorTests.pressTime

    /// Reads what the activity stream says until it goes false again after having been true.
    private static func readUntilIdle(_ activity: inout AsyncStream<Bool>.Iterator) async -> [Bool] {
        var seen: [Bool] = []
        while let value = await activity.next() {
            seen.append(value)
            if value == false, seen.contains(true) { break }
        }
        return seen
    }

    @Test("it is false at first, true from the press to the end of the dictation, and false again")
    func wholeDictation() async {
        var h = await Harness()
        var activity = h.sut.activity.makeAsyncIterator()
        #expect(await activity.next() == false)
        await h.startRecording()
        _ = await h.release()

        #expect(await Self.readUntilIdle(&activity) == [true, false])
    }

    @Test("a tap that is discarded disarms it")
    func tapDiscard() async {
        var h = await Harness()
        var activity = h.sut.activity.makeAsyncIterator()
        _ = await activity.next()
        await h.startRecording()
        _ = await h.release(after: 100)

        #expect(await Self.readUntilIdle(&activity) == [true, false])
    }

    @Test("it stays true while another dictation is in flight, and falls only after the last one ends")
    func overlap() async {
        let recognizer = FakeRecognizer(transcripts: ["uno", "dos"], gated: true)
        var h = await Harness(recognizer: recognizer)
        var activity = h.sut.activity.makeAsyncIterator()
        _ = await activity.next()
        await h.startProcessing()
        await h.sut.handle(.down(at: Self.pressTime + .milliseconds(1300)))
        h.capture.emit(AudioChunk(samples: DictationCoordinatorTests.audio(0.7)))
        _ = await h.read(through: .recording(.hold))
        await h.sut.handle(.up(at: Self.pressTime + .milliseconds(2500)))
        recognizer.releaseTranscription()
        recognizer.releaseTranscription()
        _ = await h.read(through: .idle)

        // One rise and one fall for both dictations: the first one ending does not disarm it.
        #expect(await Self.readUntilIdle(&activity) == [true, false])
        #expect(h.inserter.insertedTexts == ["uno", "dos"])
    }

    @Test("a cancelled recording disarms it, and so does a failed start")
    func cancelAndFailure() async {
        var h = await Harness()
        var activity = h.sut.activity.makeAsyncIterator()
        _ = await activity.next()
        await h.startRecording()
        await h.sut.cancel()
        #expect(await Self.readUntilIdle(&activity) == [true, false])

        var denied = await Harness(permissions: FakePermissionsChecker([.microphone: .denied]))
        var deniedActivity = denied.sut.activity.makeAsyncIterator()
        _ = await deniedActivity.next()
        await denied.sut.handle(.down(at: .zero))
        _ = await denied.read(through: .idle)
        await denied.sut.shutdown()

        // A press that fails before it records never arms Esc.
        #expect(await deniedActivity.next() == nil)
    }
}
