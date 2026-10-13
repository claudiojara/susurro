import FluidAudioASR
import Testing

@Suite("SusurroInference module smoke")
struct ModuleSmokeTests {
    @Test("the module marker names its package")
    func moduleNameMatchesPackage() {
        #expect(SusurroInferenceModule.name == "SusurroInference")
    }
}
