import Foundation
import Observation
import Synchronization
import Testing

@testable import DesignSystem

@Suite("Interface locale")
struct InterfaceLocaleTests {
    @Test("a fresh holder shows English until the app sets the language")
    func defaultIsEnglish() {
        #expect(InterfaceLocale().languageCode == "en")
    }

    @Test("a language set on the holder is the one it reports")
    func set() {
        let holder = InterfaceLocale()
        holder.set("es")
        #expect(holder.languageCode == "es")
    }

    @MainActor
    @Test("a view that read the language is told when it changes, so the words change without a relaunch")
    func observable() {
        let holder = InterfaceLocale()
        let changed = Mutex(false)
        withObservationTracking {
            _ = holder.languageCode
        } onChange: {
            changed.withLock { $0 = true }
        }
        holder.set("es")
        #expect(changed.withLock { $0 })
    }

    @Test("the language of a task can be pinned, so a test does not touch the app's language")
    func taskOverride() {
        InterfaceLocale.$override.withValue("es") {
            #expect(InterfaceLocale.current == "es")
            #expect(InterfaceLocale.locale.language.languageCode == "es")
        }
    }
}
