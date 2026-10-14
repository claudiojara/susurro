import DesignSystem
import Domain
import Testing

@testable import Presentation

/// A window title is AppKit, not SwiftUI, so nothing redraws it: `followLanguage` sets it again whenever the language it
/// read changes.
@MainActor
@Suite("Follow the language", .timeLimit(.minutes(1)))
struct FollowLanguageTests {
    final class Sink { var values: [String] = [] }

    @Test("the text is applied at once and again after every change of the language")
    func reapplies() async throws {
        let holder = InterfaceLocale()
        let sink = Sink()
        followLanguage { sink.values.append(holder.languageCode) }
        #expect(sink.values == ["en"])
        holder.set("es")
        try await waitUntil { sink.values == ["en", "es"] }
        holder.set("en")
        try await waitUntil { sink.values == ["en", "es", "en"] }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
        #expect(condition())
    }
}

@Suite("Apply the interface language")
struct ApplyInterfaceLanguageTests {
    @Test("a chosen language is shown whatever the system prefers, and System follows the preferred languages")
    func apply() {
        let holder = InterfaceLocale()
        InterfaceLanguage.spanish.apply(preferredLanguages: ["en-US"], to: holder)
        #expect(holder.languageCode == "es")
        InterfaceLanguage.english.apply(preferredLanguages: ["es-CL"], to: holder)
        #expect(holder.languageCode == "en")
        InterfaceLanguage.system.apply(preferredLanguages: ["es-CL", "en-US"], to: holder)
        #expect(holder.languageCode == "es")
    }
}
