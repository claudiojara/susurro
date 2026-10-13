import Testing

import Permissions

@Suite("SusurroPlatform module smoke")
struct ModuleSmokeTests {
    @Test("the module marker names its package")
    func moduleNameMatchesPackage() {
        #expect(SusurroPlatformModule.name == "SusurroPlatform")
    }
}
