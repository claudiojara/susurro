import CoreTestSupport
import Domain
import Testing

@testable import Pipeline

@Suite("Cleaner registry")
struct CleanerRegistryTests {
    private static let cloudID = CleanerProviderID("anthropic")

    private let local = FakeCleaner(id: .appleIntelligence, locality: .local)
    private let cloud = FakeCleaner(id: Self.cloudID, locality: .cloud)

    private func registry(
        settings: InMemorySettingsStore, enabled: Bool = false, hasKey: Bool = false
    ) -> CleanerRegistry {
        CleanerRegistry(
            settings: settings,
            entries: [
                .local(local),
                .cloud(cloud, isEnabled: { enabled }, hasKey: { hasKey }),
            ])
    }

    @Test("a fresh install resolves Apple's on-device cleaner")
    func defaultProvider() {
        let resolution = registry(settings: InMemorySettingsStore()).resolve()
        #expect(resolution.cleaner?.id == .appleIntelligence)
        #expect(resolution.cleaner?.locality == .local)
    }

    @Test("the selection persists across a relaunch")
    func selectionPersists() {
        let settings = InMemorySettingsStore()
        registry(settings: settings, enabled: true, hasKey: true).select(Self.cloudID)
        let relaunched = registry(settings: settings, enabled: true, hasKey: true)
        #expect(relaunched.selectedID == Self.cloudID)
        #expect(relaunched.resolve().cleaner?.id == Self.cloudID)
    }

    @Test("a cloud cleaner is unusable until it is enabled and has a key")
    func cloudNeedsOptInAndKey() {
        let settings = InMemorySettingsStore()
        settings.set(Self.cloudID.rawValue, for: CleanupSettings.provider)
        #expect(registry(settings: settings, enabled: false, hasKey: true).resolve().unusableReason == .notEnabled)
        #expect(registry(settings: settings, enabled: true, hasKey: false).resolve().unusableReason == .missingKey)
        #expect(registry(settings: settings, enabled: false, hasKey: false).resolve().unusableReason == .notEnabled)
        #expect(registry(settings: settings, enabled: true, hasKey: true).resolve().cleaner?.id == Self.cloudID)
    }

    @Test("an unusable selection resolves no cleaner, so the raw transcript is used")
    func unusableSelectionResolvesNothing() {
        let settings = InMemorySettingsStore()
        settings.set(Self.cloudID.rawValue, for: CleanupSettings.provider)
        #expect(registry(settings: settings).resolve().cleaner == nil)
    }

    @Test("a selection that is not registered falls back to the default")
    func unknownSelectionFallsBack() {
        let settings = InMemorySettingsStore()
        settings.set("removed-provider", for: CleanupSettings.provider)
        #expect(registry(settings: settings).resolve().cleaner?.id == .appleIntelligence)
    }
}
