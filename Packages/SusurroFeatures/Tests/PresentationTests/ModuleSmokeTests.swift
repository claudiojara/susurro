import Testing

import Presentation

@Suite("SusurroFeatures module smoke")
struct ModuleSmokeTests {
    @Test("the module marker names its package")
    func moduleNameMatchesPackage() {
        #expect(SusurroFeaturesModule.name == "SusurroFeatures")
    }
}
