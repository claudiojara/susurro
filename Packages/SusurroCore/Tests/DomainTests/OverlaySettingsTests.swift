import Domain
import Testing

@Suite("Overlay settings")
struct OverlaySettingsTests {
    @Test("the settings screen and the overlay read one key with one default, the pill")
    func oneKey() {
        #expect(GeneralSettings.overlayVariant.storageName == OverlaySettings.variant.storageName)
        #expect(GeneralSettings.overlayVariant.defaultValue == "pill")
    }

    @Test("a stored id selects itself, and the id older settings stored for the default selects the pill")
    func storedIDs() {
        #expect(OverlaySettings.variantID(stored: "liveText") == "liveText")
        #expect(OverlaySettings.variantID(stored: "default") == "pill")
        #expect(OverlaySettings.variantID(stored: "pill") == "pill")
    }
}
