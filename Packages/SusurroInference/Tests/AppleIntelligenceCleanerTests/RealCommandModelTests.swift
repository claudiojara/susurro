import Domain
import Foundation
import Testing
import TextShaping

@testable import AppleIntelligenceCleaner

/// Command mode against Apple's real on-device model, off unless `SUSURRO_REAL_MODELS=1` (see `RealModelTests`):
///
///     SUSURRO_REAL_MODELS=1 swift test --package-path Packages/SusurroInference --filter RealCommandModelTests
///
/// Each check prints the reply and how long it took, which is what the timeout of a rewrite is tuned on
/// (`CommandLimits.timeout`). What the app promises is what the guard lets through, so the checks look at that.
@Suite(
    "Real Apple Intelligence model, command mode",
    .enabled(
        if: ProcessInfo.processInfo.environment["SUSURRO_REAL_MODELS"] == "1",
        "Set SUSURRO_REAL_MODELS=1 to check against the real model."),
    .serialized,
    .timeLimit(.minutes(10))
)
struct RealCommandModelTests {
    private static let selection = """
        oye equipo, mañana no voy a poder ir a la reunión de las diez porque tengo que llevar el coche al taller, \
        si alguien puede tomar notas se lo agradezco, y el informe lo mando el viernes sin falta
        """

    /// The reply and the guard's verdict on it. Nil when Apple Intelligence is not available.
    private func command(_ instruction: String) async throws -> CommandOutputGuard.Verdict? {
        let rewriter = AppleIntelligenceRewriter()
        guard await rewriter.availability() == .available else { return nil }
        let clock = ContinuousClock()
        let started = clock.now
        let output = try await rewriter.rewrite(
            LocalCommandRequest(instruction: instruction, selection: Self.selection))
        let elapsed = started.duration(to: clock.now)
        let limit = CommandLimits.timeout(instruction: instruction.count, selection: Self.selection.count)
        print("\(instruction) -> [\(elapsed), limit \(limit)]", output)
        return CommandOutputGuard.evaluate(selection: Self.selection, instruction: instruction, output: output)
    }

    @Test(
        "a command is applied and passes the guard",
        arguments: ["hazlo más formal", "tradúcelo al inglés", "resume en 3 viñetas"])
    func applied(instruction: String) async throws {
        guard let verdict = try await command(instruction) else { return }
        guard case .accepted(let text) = verdict else {
            Issue.record("rejected: \(verdict)")
            return
        }
        #expect(!SelectionReader.isSame(text, Self.selection))
    }
}
