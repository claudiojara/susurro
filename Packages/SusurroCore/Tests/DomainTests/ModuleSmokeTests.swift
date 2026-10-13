import Domain
import Testing

@Suite("SusurroCore module smoke")
struct ModuleSmokeTests {
    @Test("the module marker names its package")
    func moduleNameMatchesPackage() {
        #expect(SusurroCoreModule.name == "SusurroCore")
    }
}
