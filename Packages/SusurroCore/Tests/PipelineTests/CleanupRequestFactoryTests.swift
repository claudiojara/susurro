import CoreTestSupport
import Domain
import Testing

@testable import Pipeline

@Suite("Cleanup request factory")
struct CleanupRequestFactoryTests {
    private let style = StyleProfile(category: .workChat, tone: .casual, source: .default)

    private func input(
        transcript: String = "hola", before: String = "", vocabulary: [String] = ["Acme"]
    ) -> CleanupInput {
        CleanupInput(
            transcript: transcript, style: style, vocabulary: vocabulary,
            cursor: CursorContext(before: before, after: "AFTER-SENTINEL"))
    }

    @Test("a cloud cleaner gets a cloud payload with no sentinel context in it")
    func cloudPayloadHasNoContext() throws {
        let cleaner = FakeCleaner(id: CleanerProviderID("cloud"), locality: .cloud)
        let payload = CleanupRequestFactory.payload(
            for: cleaner, input: input(before: "BEFORE-SENTINEL"))
        let request = try payload.requireCloud()
        #expect(request == CloudCleanupRequest(transcript: "hola", style: style, vocabulary: ["Acme"]))
        let dump = String(reflecting: payload)
        for sentinel in ["BEFORE-SENTINEL", "AFTER-SENTINEL"] { #expect(!dump.contains(sentinel)) }
        #expect(throws: CloudBoundaryViolation.self) { try payload.requireLocal() }
    }

    @Test("a local cleaner gets a local payload with the bounded text before the cursor")
    func localPayloadCarriesBoundedBeforeText() throws {
        let cleaner = FakeCleaner(locality: .local)
        let before = String(repeating: "a", count: 700) + "END"
        let payload = CleanupRequestFactory.payload(for: cleaner, input: input(before: before))
        let request = try payload.requireLocal()
        #expect(request.beforeCursor.count == CleanupRequestFactory.beforeCursorLimit)
        #expect(request.beforeCursor.hasSuffix("END"))
        #expect(request.vocabulary == ["Acme"])
        #expect(!String(reflecting: payload).contains("AFTER-SENTINEL"))
    }

    @Test("an unknown surrounding gives a local payload with no context")
    func unknownCursor() throws {
        let cleaner = FakeCleaner(locality: .local)
        let payload = CleanupRequestFactory.payload(
            for: cleaner, input: CleanupInput(transcript: "hola", style: style))
        #expect(try payload.requireLocal().beforeCursor.isEmpty)
    }

    @Test("the text before the cursor shrinks so that it and the transcript fit the budget")
    func beforeTextTrimmedToBudget() throws {
        let budget = ProviderBudget(maxTranscriptCharacters: 100, maxInputCharacters: 120, timeout: .seconds(1))
        let cleaner = FakeCleaner(locality: .local, budget: budget)
        let transcript = String(repeating: "t", count: 100)
        let payload = CleanupRequestFactory.payload(
            for: cleaner, input: input(transcript: transcript, before: String(repeating: "b", count: 400)))
        #expect(try payload.requireLocal().beforeCursor.count == 20)
        let full = CleanupRequestFactory.payload(
            for: cleaner, input: input(transcript: String(repeating: "t", count: 130), before: "bbb"))
        #expect(try full.requireLocal().beforeCursor.isEmpty)
    }

    @Test("grapheme clusters are never split when the text is trimmed")
    func graphemeClustersStayWhole() throws {
        let cleaner = FakeCleaner(locality: .local)
        let family = "👨‍👩‍👧"
        let before = String(repeating: family, count: CleanupRequestFactory.beforeCursorLimit + 5)
        let request = try CleanupRequestFactory.payload(for: cleaner, input: input(before: before)).requireLocal()
        #expect(request.beforeCursor.count == CleanupRequestFactory.beforeCursorLimit)
        #expect(request.beforeCursor.hasPrefix(family))
    }
}
