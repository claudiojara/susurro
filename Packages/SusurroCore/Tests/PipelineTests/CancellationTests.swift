import CoreTestSupport
import Domain
import Pipeline
import Testing

@Suite("Cancelling a dictation", .timeLimit(.minutes(1)))
struct CancellationTests {
    private typealias Harness = CoordinatorHarness
    private static let pressTime = DictationCoordinatorTests.pressTime

    @Test("cancelling while recording keeps a cancelled record with its audio, and transcribes and inserts nothing")
    func cancelWhileRecording() async throws {
        var h = await Harness()
        await h.startRecording()
        await h.sut.cancel()
        let states = await h.read(through: .idle)

        #expect(states == [.idle])
        let record = try #require(try await h.history.page(offset: 0, limit: 10).first)
        #expect(record.status == .cancelled)
        #expect(record.audioURL == FakeRecordingStore.url(for: SessionID(record.id)))
        #expect(h.recordings.aborted.isEmpty)
        #expect(h.recordings.finished.count == 1)
        #expect(h.recognizer.transcribedClips.isEmpty)
        #expect(h.inserter.insertedTexts.isEmpty)
    }

    @Test("the release that follows a cancelled recording does nothing")
    func releaseAfterCancel() async {
        var h = await Harness()
        await h.startRecording()
        await h.sut.cancel()
        _ = await h.read(through: .idle)
        await h.sut.handle(.up(at: Self.pressTime + .milliseconds(1200)))

        #expect(h.capture.startCount == 1)
        #expect(h.inserter.insertedTexts.isEmpty)
    }

    @Test("cancelling during transcription drops the text that comes back later, and keeps the record and the audio")
    func cancelDuringTranscription() async throws {
        let recognizer = FakeRecognizer(transcript: "tarde", gated: true)
        var h = await Harness(recognizer: recognizer)
        await h.startProcessing()
        await recognizer.transcribeEntered.wait()
        await h.sut.cancel()
        recognizer.releaseTranscription()  // the recognizer answers after the cancellation
        let states = await h.read(through: .idle)

        #expect(states == [.idle])
        #expect(h.inserter.insertedTexts.isEmpty)
        let record = try #require(try await h.history.page(offset: 0, limit: 10).first)
        #expect(record.status == .cancelled)
        #expect(record.audioURL != nil)
        #expect(h.recordings.aborted.isEmpty)
    }

    @Test("cancelling twice, or with nothing in flight, does nothing")
    func nothingToCancel() async {
        var h = await Harness()
        await h.sut.cancel()
        await h.startRecording()
        _ = await h.release()
        await h.sut.cancel()

        #expect(h.inserter.insertedTexts == ["hello"])
    }

    @Test("cancelling cancels the newest dictation only: the one before it is still inserted")
    func cancelsTheNewest() async throws {
        let recognizer = FakeRecognizer(transcripts: ["uno", "dos"], gated: true)
        var h = await Harness(recognizer: recognizer)
        await h.startProcessing()
        await h.sut.handle(.down(at: Self.pressTime + .milliseconds(1300)))
        h.capture.emit(AudioChunk(samples: DictationCoordinatorTests.audio(0.7)))
        _ = await h.read(through: .recording(.hold))
        await h.sut.handle(.up(at: Self.pressTime + .milliseconds(2500)))
        // The second dictation waits behind the first; Esc is for the one just spoken.
        await h.sut.cancel()
        recognizer.releaseTranscription()
        _ = await h.read(through: .idle)

        #expect(h.inserter.insertedTexts == ["uno"])
        let records = try await h.history.page(offset: 0, limit: 10)
        #expect(Set(records.map(\.status)) == [.succeeded, .cancelled])
        #expect(records.allSatisfy { $0.audioURL != nil })
        #expect(recognizer.transcribedClips.count == 1)
    }

    @Test("a record is made for every kept recording before the recognizer is invoked")
    func recordBeforeRecognition() async throws {
        let history = InMemoryHistoryRepository()
        let recognizer = FakeRecognizer(transcript: "hola", gated: true)
        var h = await Harness(recognizer: recognizer, history: history)
        await h.startProcessing()
        await recognizer.transcribeEntered.wait()

        // The recognizer is in its call: the record exists already, as processing, with the audio.
        let record = try #require(try await history.page(offset: 0, limit: 10).first)
        #expect(record.status == .processing)
        #expect(record.audioURL != nil)
        recognizer.releaseTranscription()
        _ = await h.read(through: .idle)
        #expect(try await history.page(offset: 0, limit: 10).first?.status == .succeeded)
    }
}
