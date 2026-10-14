import Domain
import Testing

@Suite("Provider budget")
struct ProviderBudgetTests {
    @Test("the on-device model gets 1.2 s plus 8 ms for each character of the transcript, up to 6 s")
    func foundationModelsTimeout() {
        let budget = ProviderBudget.foundationModels
        #expect(budget.timeout(forTranscriptCharacters: 0) == .milliseconds(1_200))
        #expect(budget.timeout(forTranscriptCharacters: 30) == .milliseconds(1_440))
        #expect(budget.timeout(forTranscriptCharacters: 79) == .milliseconds(1_832))
        #expect(budget.timeout(forTranscriptCharacters: 300) == .milliseconds(3_600))
        #expect(budget.timeout(forTranscriptCharacters: 599) == .milliseconds(5_992))
        #expect(budget.timeout(forTranscriptCharacters: 600) == .seconds(6))
        #expect(budget.timeout(forTranscriptCharacters: 2_500) == .seconds(6))
    }

    @Test("a cloud cleaner gets 6 s whatever the length")
    func cloudTimeout() {
        let budget = ProviderBudget.cloud
        for characters in [0, 30, 3_000, 6_000] {
            #expect(budget.timeout(forTranscriptCharacters: characters) == .seconds(6))
        }
    }

    @Test("a budget with one flat limit gives it for every length")
    func flatTimeout() {
        let budget = ProviderBudget(maxTranscriptCharacters: 100, maxInputCharacters: 120, timeout: .seconds(1))
        for characters in [0, 50, 100] {
            #expect(budget.timeout(forTranscriptCharacters: characters) == .seconds(1))
        }
    }

    @Test("the limits of the input are the ones the design measured")
    func inputLimits() {
        #expect(ProviderBudget.foundationModels.maxTranscriptCharacters == 2_500)
        #expect(ProviderBudget.foundationModels.maxInputCharacters == 2_800)
        #expect(ProviderBudget.cloud.maxTranscriptCharacters == 6_000)
    }
}
