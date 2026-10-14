import Domain

/// The cleaners the app knows and the one the user selected. A local cleaner is always usable. A cloud cleaner is
/// unusable until the user enabled it and a key exists for it, so nothing leaves the Mac by default.
public struct CleanerRegistry: Sendable {
    /// Why a registered cleaner cannot be used.
    public enum Unusable: Sendable, Equatable {
        /// A cloud cleaner the user has not turned on.
        case notEnabled
        /// A cloud cleaner that is on and has no key.
        case missingKey
    }

    /// A cleaner and the rule for using it.
    public struct Entry: Sendable {
        let cleaner: any TranscriptCleaner
        let unusableReason: @Sendable () -> Unusable?

        /// A cleaner that runs on this Mac.
        public static func local(_ cleaner: any TranscriptCleaner) -> Entry {
            Entry(cleaner: cleaner, unusableReason: { nil })
        }

        /// A cleaner that sends the request to a service: usable once it is enabled and its key exists.
        public static func cloud(
            _ cleaner: any TranscriptCleaner,
            isEnabled: @escaping @Sendable () -> Bool,
            hasKey: @escaping @Sendable () -> Bool
        ) -> Entry {
            Entry(
                cleaner: cleaner,
                unusableReason: { !isEnabled() ? .notEnabled : !hasKey() ? .missingKey : nil })
        }
    }

    /// What the selection resolves to now.
    public struct Resolution: Sendable {
        public let cleaner: (any TranscriptCleaner)?
        public let unusableReason: Unusable?
    }

    private let settings: any SettingsStore
    private let entries: [Entry]

    public init(settings: any SettingsStore, entries: [Entry]) {
        self.settings = settings
        self.entries = entries
    }

    /// The id the user selected. A fresh install selects Apple's on-device cleaner.
    public var selectedID: CleanerProviderID {
        CleanerProviderID(settings.value(for: CleanupSettings.provider))
    }

    public func select(_ id: CleanerProviderID) {
        settings.set(id.rawValue, for: CleanupSettings.provider)
    }

    /// The selected cleaner, if it can be used. A selection that is no longer registered gives the default cleaner.
    public func resolve() -> Resolution {
        let entry =
            entries.first { $0.cleaner.id == selectedID }
            ?? entries.first { $0.cleaner.id == .appleIntelligence }
        guard let entry else { return Resolution(cleaner: nil, unusableReason: nil) }
        if let reason = entry.unusableReason() { return Resolution(cleaner: nil, unusableReason: reason) }
        return Resolution(cleaner: entry.cleaner, unusableReason: nil)
    }
}
