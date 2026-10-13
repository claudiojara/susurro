import SusurroUI
import Testing

@MainActor
@Suite("SusurroUI module smoke")
struct ModuleSmokeTests {
    @Test("the module marker names its package")
    func moduleNameMatchesPackage() {
        #expect(SusurroUIModule.name == "SusurroUI")
    }
}
