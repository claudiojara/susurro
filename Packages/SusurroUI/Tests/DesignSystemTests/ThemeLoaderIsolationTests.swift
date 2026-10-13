import Foundation
import Testing

@testable import DesignSystem

/// The design system compiles with the main actor as its default isolation. These tests are in a nonisolated suite
/// and call the loader from a detached task, so they stop compiling if the loader or the theme types ever lose
/// `nonisolated`.
@Suite("Theme loader isolation")
struct ThemeLoaderIsolationTests {
    @Test("the loader runs from a detached task")
    func loadsOffTheMainActor() async {
        let data = Data(#"{"schemaVersion": 1, "spacing": {"md": 14}}"#.utf8)
        let result = await Task.detached { ThemeLoader.load(data: data) }.value
        #expect(result.theme.spacing["md"] == 14)
        #expect(result.errors == [])
    }

    @Test("a file with an error reports it from a detached task too")
    func reportsOffTheMainActor() async {
        let result = await Task.detached { ThemeLoader.load(data: Data("{".utf8)) }.value
        #expect(result.errors.count == 1)
        #expect(result.theme == (await Task.detached { Theme.default }.value))
    }
}
