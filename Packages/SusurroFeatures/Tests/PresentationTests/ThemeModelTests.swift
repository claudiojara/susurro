import DesignSystem
import Foundation
import Testing

@testable import Presentation

@MainActor
@Suite("Theme model", .timeLimit(.minutes(1)))
struct ThemeModelTests {
    /// A theme file that changes only the name, and one that cannot be used.
    private func result(named name: String) -> ThemeLoadResult {
        ThemeLoader.load(data: Data(#"{"schemaVersion": 1, "name": "\#(name)"}"#.utf8))
    }

    private let broken = ThemeLoader.load(data: Data(#"{"schemaVersion": 1, "colours": {}}"#.utf8))

    @Test("it starts with the bundled theme and nothing wrong with it")
    func startsWithTheDefault() {
        let model = ThemeModel()

        #expect(model.theme == .default)
        #expect(model.errors.isEmpty)
    }

    @Test("it takes the theme of each result the store publishes, until the stream ends")
    func followsTheStore() async {
        let model = ThemeModel()
        let (updates, continuation) = AsyncStream.makeStream(of: ThemeLoadResult.self)
        let following = Task { await model.follow(updates) }

        continuation.yield(result(named: "Ocean"))
        await waitUntil { model.theme.name == "Ocean" }
        continuation.yield(result(named: "Forest"))
        await waitUntil { model.theme.name == "Forest" }
        continuation.finish()
        await following.value

        #expect(model.theme.name == "Forest")
        #expect(model.errors.isEmpty)
    }

    @Test("a file that cannot be used shows the bundled theme and its errors, and a good file clears them")
    func showsTheErrorsOfAFile() async {
        let model = ThemeModel()
        let (updates, continuation) = AsyncStream.makeStream(of: ThemeLoadResult.self)
        let following = Task { await model.follow(updates) }

        continuation.yield(broken)
        await waitUntil { !model.errors.isEmpty }
        let whileBroken = (theme: model.theme, errors: model.errors)
        continuation.yield(result(named: "Ocean"))
        await waitUntil { model.errors.isEmpty }
        continuation.finish()
        await following.value

        #expect(!broken.errors.isEmpty)
        #expect(whileBroken.theme == .default)
        #expect(whileBroken.errors == broken.errors)
        #expect(model.theme.name == "Ocean")
    }
}
