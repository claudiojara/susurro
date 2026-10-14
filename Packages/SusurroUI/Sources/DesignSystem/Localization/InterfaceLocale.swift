import Foundation
import Observation
import Synchronization

/// The language the app shows its own words in, by its code (`en` or `es`). The app sets it at launch and whenever the
/// user picks another one in Settings. Every sentence is looked up through `string(_:_:bundle:)`, which reads it, and the
/// holder is observable, so a view that showed a sentence is drawn again in the new language without a relaunch.
///
/// A task can pin its own language with `$override`, which leaves the app's language alone: tests use it, since they run
/// side by side.
public nonisolated final class InterfaceLocale: Observable, Sendable {
    /// The app's language. It is English until the app sets it.
    public static let shared = InterfaceLocale()

    /// The language of the current task, when one is pinned. It wins over the app's.
    @TaskLocal public static var override: String?

    private let code: Mutex<String>
    private let registrar = ObservationRegistrar()

    public init(languageCode: String = "en") {
        code = Mutex(languageCode)
    }

    public var languageCode: String {
        registrar.access(self, keyPath: \.languageCode)
        return code.withLock { $0 }
    }

    /// Shows the app's words in another language. Setting the language in use again changes nothing.
    public func set(_ languageCode: String) {
        guard languageCode != code.withLock({ $0 }) else { return }
        registrar.withMutation(of: self, keyPath: \.languageCode) {
            code.withLock { $0 = languageCode }
        }
    }

    /// The code of the language to show now: the task's, else the app's.
    public static var current: String { override ?? shared.languageCode }

    /// The locale of that language, for numbers and dates in a sentence.
    public static var locale: Locale { Locale(identifier: current) }

    /// The sentence under `key` in the string catalog of `bundle`, in the current language. The English text is what
    /// the sentence is when the catalog lacks the key, so a missing entry shows English and never the key.
    public static func string(
        _ key: StaticString, _ defaultValue: String.LocalizationValue, bundle: Bundle
    ) -> String {
        let language = current
        return String(
            localized: key, defaultValue: defaultValue, bundle: LanguageBundles.bundle(for: language, in: bundle),
            locale: Locale(identifier: language))
    }
}

/// The folder of one language inside a resource bundle (`es.lproj`), opened once. A catalog is looked up in it so that
/// the sentence comes in the chosen language, whatever languages the system prefers.
nonisolated enum LanguageBundles {
    private static let cache = Mutex<[String: Bundle]>([:])

    static func bundle(for language: String, in bundle: Bundle) -> Bundle {
        let key = "\(bundle.bundlePath)#\(language)"
        if let cached = cache.withLock({ $0[key] }) { return cached }
        let found = bundle.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? bundle
        cache.withLock { $0[key] = found }
        return found
    }
}
