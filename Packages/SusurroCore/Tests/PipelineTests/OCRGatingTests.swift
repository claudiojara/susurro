import CoreTestSupport
import Domain
import Synchronization
import Testing
import TextShaping

@testable import Pipeline

@Suite("OCR gating", .timeLimit(.minutes(1)))
struct OCRGatingTests {
    private static let mail = AppIdentity(processID: 10, name: "Mail", bundleID: "com.apple.mail", windowTitle: "Inbox")
    private static let slack = AppIdentity(processID: 20, name: "Slack", bundleID: "com.tinyspeck.slackmacgap")
    private static let sentinel = "OCR-SENTINEL Acme Corp"

    /// The frontmost app, which a test changes while a read is under way.
    private final class Frontmost: Sendable {
        private let app = Mutex<AppIdentity?>(OCRGatingTests.mail)
        func set(_ app: AppIdentity?) { self.app.withLock { $0 = app } }
        func current() -> AppIdentity? { app.withLock { $0 } }
    }

    private func enrichment(
        enabled: Bool = true, screenRecording: PermissionStatus = .granted,
        recognizer: FakeScreenTextRecognizer, frontmost: Frontmost = Frontmost()
    ) -> ContextEnrichment {
        let settings = InMemorySettingsStore()
        if enabled { settings.set(true, for: ContextSettings.ocrEnabled) }
        return ContextEnrichment(
            settings: settings, permissions: FakePermissionsChecker([.screenRecording: screenRecording]),
            recognizer: recognizer, frontmost: { frontmost.current() })
    }

    @Test("OCR is off by default and the recognizer is not called")
    func offByDefault() async {
        let recognizer = FakeScreenTextRecognizer(lines: [Self.sentinel])
        let lines = await enrichment(enabled: false, recognizer: recognizer).screenText(
            for: Self.mail, isSecureField: false)
        #expect(lines.isEmpty)
        #expect(recognizer.callCount == 0)
    }

    @Test(
        "OCR that is on without Screen Recording skips silently", arguments: [PermissionStatus.denied, .notDetermined])
    func permissionMissing(status: PermissionStatus) async {
        let recognizer = FakeScreenTextRecognizer(lines: [Self.sentinel])
        let lines = await enrichment(screenRecording: status, recognizer: recognizer).screenText(
            for: Self.mail, isSecureField: false)
        #expect(lines.isEmpty)
        #expect(recognizer.callCount == 0)
    }

    @Test("OCR that is on and granted reads the window of the frontmost app")
    func onAndGranted() async {
        let recognizer = FakeScreenTextRecognizer(lines: ["Acme Corp", "Maria Gonzalez"])
        let lines = await enrichment(recognizer: recognizer).screenText(for: Self.mail, isSecureField: false)
        #expect(lines == ["Acme Corp", "Maria Gonzalez"])
        #expect(recognizer.recognizedApps == [Self.mail])
    }

    @Test("a secure field skips OCR")
    func secureField() async {
        let recognizer = FakeScreenTextRecognizer(lines: [Self.sentinel])
        let lines = await enrichment(recognizer: recognizer).screenText(for: Self.mail, isSecureField: true)
        #expect(lines.isEmpty)
        #expect(recognizer.callCount == 0)
    }

    @Test("a frontmost app that changes before the read ends discards the result")
    func appChanged() async {
        let recognizer = FakeScreenTextRecognizer(lines: [Self.sentinel], gated: true)
        let frontmost = Frontmost()
        let sut = enrichment(recognizer: recognizer, frontmost: frontmost)
        let reading = Task { await sut.screenText(for: Self.mail, isSecureField: false) }
        await recognizer.entered.wait()
        frontmost.set(Self.slack)
        recognizer.release()
        #expect(await reading.value.isEmpty)
    }

    @Test("a window that changes before the read ends discards the result")
    func windowChanged() async {
        let recognizer = FakeScreenTextRecognizer(lines: [Self.sentinel], gated: true)
        let frontmost = Frontmost()
        let sut = enrichment(recognizer: recognizer, frontmost: frontmost)
        let reading = Task { await sut.screenText(for: Self.mail, isSecureField: false) }
        await recognizer.entered.wait()
        frontmost.set(AppIdentity(processID: 10, name: "Mail", bundleID: "com.apple.mail", windowTitle: "Drafts"))
        recognizer.release()
        #expect(await reading.value.isEmpty)
    }

    @Test("a cancelled dictation drops the result")
    func cancelled() async {
        let recognizer = FakeScreenTextRecognizer(lines: [Self.sentinel], gated: true)
        let sut = enrichment(recognizer: recognizer)
        let reading = Task { await sut.screenText(for: Self.mail, isSecureField: false) }
        await recognizer.entered.wait()
        reading.cancel()
        recognizer.release()
        #expect(await reading.value.isEmpty)
    }

    @Test("a superseded dictation drops the result")
    func superseded() async {
        let recognizer = FakeScreenTextRecognizer(lines: [Self.sentinel])
        let lines = await enrichment(recognizer: recognizer).screenText(
            for: Self.mail, isSecureField: false, isCurrent: { false })
        #expect(lines.isEmpty)
    }

    @Test("a recognizer that fails gives no text and no error")
    func recognizerFails() async {
        struct Failure: Error {}
        let recognizer = FakeScreenTextRecognizer(failure: Failure())
        let lines = await enrichment(recognizer: recognizer).screenText(for: Self.mail, isSecureField: false)
        #expect(lines.isEmpty)
    }

    @Test("screen text reaches the tagger and the vocabulary builder, and no cleanup request")
    func screenTextStaysOutOfTheRequests() async throws {
        let recognizer = FakeScreenTextRecognizer(lines: [Self.sentinel])
        let lines = await enrichment(recognizer: recognizer).screenText(for: Self.mail, isSecureField: false)
        let tagger = FakeEntityTagger([Self.sentinel: ["Acme Corp"]])
        let vocabulary = VocabularyBuilder(tagger: tagger).build(VocabularySources(screenText: lines))
        #expect(tagger.taggedTexts == [Self.sentinel])
        #expect(vocabulary == ["Acme Corp"])

        let style = StyleProfile(category: .email, tone: .formal)
        let input = CleanupInput(
            transcript: "hola", style: style, vocabulary: vocabulary,
            cursor: CursorContext(before: "Dear", after: ""))
        for locality in [Locality.local, .cloud] {
            let payload = CleanupRequestFactory.payload(for: FakeCleaner(locality: locality), input: input)
            #expect(!String(reflecting: payload).contains("OCR-SENTINEL"))
        }
    }
}
