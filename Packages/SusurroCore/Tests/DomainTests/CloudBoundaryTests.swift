import Domain
import Testing

@Suite("Cloud data boundary")
struct CloudBoundaryTests {
    @Test("a cloud request holds the transcript, the style, and the vocabulary, and nothing else")
    func storedPropertiesAreFixed() {
        let request = CloudCleanupRequest(
            transcript: "hola", style: StyleProfile(category: .email, tone: .formal, source: .default),
            vocabulary: ["Acme"])
        let labels = Mirror(reflecting: request).children.compactMap(\.label)
        #expect(Set(labels) == ["transcript", "style", "vocabulary"])
        #expect(labels.count == 3)
    }

    @Test("a local request adds only the text before the cursor")
    func localAddsOnlyBeforeCursor() {
        let request = LocalCleanupRequest(
            transcript: "hola", style: StyleProfile(category: .email, tone: .formal, source: .default), vocabulary: [],
            beforeCursor: "x")
        let labels = Mirror(reflecting: request).children.compactMap(\.label)
        #expect(Set(labels) == ["transcript", "style", "vocabulary", "beforeCursor"])
    }

    @Test("requireCloud refuses a local payload and requireLocal refuses a cloud one")
    func requireGuards() throws {
        let style = StyleProfile(category: .other, tone: .neutral, source: .default)
        let local = CleanupPayload.local(
            LocalCleanupRequest(transcript: "a", style: style, vocabulary: [], beforeCursor: "b"))
        let cloud = CleanupPayload.cloud(CloudCleanupRequest(transcript: "a", style: style, vocabulary: []))
        #expect(throws: CloudBoundaryViolation.self) { try local.requireCloud() }
        #expect(throws: CloudBoundaryViolation.self) { try cloud.requireLocal() }
        #expect(try cloud.requireCloud().transcript == "a")
        #expect(try local.requireLocal().beforeCursor == "b")
    }

    @Test("an error a cleaner threw maps to its fallback reason")
    func thrownErrorsMapToReasons() {
        #expect(FallbackReason(thrownBy: CleanerError.guardrail) == .guardrail)
        #expect(FallbackReason(thrownBy: CleanerError.contextWindowExceeded) == .inputTooLarge)
        #expect(FallbackReason(thrownBy: CleanerError.unavailable("off")) == .providerFailure)
        #expect(FallbackReason(thrownBy: CleanerError.failed("x")) == .providerFailure)
        struct Other: Error {}
        #expect(FallbackReason(thrownBy: Other()) == .providerFailure)
    }
}
