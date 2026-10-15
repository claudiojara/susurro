import CoreTestSupport
import Domain
import Testing

@testable import Composition

@MainActor
@Suite("App environment: learning dictionary")
struct AppEnvironmentLearningTests {
    private let sleep: @Sendable (Duration) async throws -> Void = { _ in }

    @Test("a graph without a field reader or a frontmost app learns nothing")
    func noSources() {
        var dependencies = AppEnvironment.Dependencies.preview()
        dependencies.frontmost = FakeFrontmostAppProvider(.mail)
        #expect(dependencies.correctionWatch(sleep: sleep) == nil)

        dependencies.frontmost = nil
        dependencies.corrections = AppEnvironment.CorrectionSources(
            reader: MutableFocusedContextReader(), tagger: FakeEntityTagger())
        #expect(dependencies.correctionWatch(sleep: sleep) == nil)
    }

    @Test("a graph with both watches the pasted dictations")
    func withSources() {
        var dependencies = AppEnvironment.Dependencies.preview()
        dependencies.frontmost = FakeFrontmostAppProvider(.mail)
        dependencies.corrections = AppEnvironment.CorrectionSources(
            reader: MutableFocusedContextReader(), tagger: FakeEntityTagger())

        #expect(dependencies.correctionWatch(sleep: sleep) != nil)
    }
}
