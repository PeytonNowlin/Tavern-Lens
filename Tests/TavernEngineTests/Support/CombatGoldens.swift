import Foundation
import Testing
import TavernEngine

/// Simulator inputs taken from the captured games at combat start, committed under
/// `Tests/TavernEngineTests/Golden/Combat/` so the simulator's golden odds run without the
/// private logs (they hold only card and entity IDs). Record them with `TAVERN_RECORD_GOLDENS=1`.
enum CombatGoldens {
    /// Full game, BG turn 11 (mapping §8.1): about a 74% loss, 7–13 damage; the real combat lost for 10.
    static let fullGameTurn11 = "full-game-turn-11"
    /// Truncated game, BG turn 4 (mapping §8.2): about a 96% loss, 3–4 damage; the real combat lost for 3.
    static let truncatedGameTurn4 = "truncated-game-turn-4"

    static let directory = GoldenHarness.goldenDirectory.appending(path: "Combat", directoryHint: .isDirectory)

    static func url(_ name: String) -> URL { directory.appending(path: "\(name).input.json") }

    static func input(_ name: String) throws -> BattleInput {
        try JSONDecoder().decode(BattleInput.self, from: Data(contentsOf: url(name)))
    }

    /// Compares `input` to the committed golden, or records it.
    static func verify(_ input: BattleInput, golden name: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
        try GoldenHarness.verify(input, at: url(name), sourceLocation: sourceLocation)
    }

    static func makeSimulator() throws -> CombatSimulator {
        let simulator = try CombatSimulator()
        try simulator.loadPinnedCards()
        return simulator
    }

    /// The seed of the golden runs: with it and a budget of simulations only, a run gives the same
    /// odds on any machine.
    static let seed: UInt32 = 20_260_922

    /// Runs `input`, seeded, on a simulator of its own. Every simulator in the process shares one
    /// JavaScript thread, so simulations queue rather than run in parallel; and the test runner has
    /// no JIT entitlement, so JavaScriptCore interprets here, several times slower than in the app.
    /// Keep test budgets small.
    static func run(_ input: BattleInput, budget: SimulationBudget = .golden) async throws -> CombatOdds {
        try await makeSimulator().simulate(input, budget: budget, seed: seed)
    }
}

extension SimulationBudget {
    /// Enough simulations for the research's percentages (about ±1 point of noise, fixed by the
    /// seed), with no time limit that could cut them short.
    static let golden = SimulationBudget(simulations: 3000, maxDurationMilliseconds: 600_000, intermediateResults: 3000)
}
