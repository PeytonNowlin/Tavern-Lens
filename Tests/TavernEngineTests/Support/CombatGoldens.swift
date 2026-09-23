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

    static func encode(_ input: BattleInput) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(input)
        data.append(0x0A)
        return data
    }

    static func input(_ name: String) throws -> BattleInput {
        try JSONDecoder().decode(BattleInput.self, from: Data(contentsOf: url(name)))
    }

    /// Compares `input` to the committed golden, or records it.
    static func verify(_ input: BattleInput, golden name: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let data = try encode(input)
        try #require(!GoldenHarness.containsBattleTag(String(decoding: data, as: UTF8.self)), sourceLocation: sourceLocation)
        if GoldenHarness.isRecording {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url(name))
            return
        }
        let expected = try #require(
            try? Self.input(name), "missing golden \(name); run with TAVERN_RECORD_GOLDENS=1", sourceLocation: sourceLocation
        )
        #expect(expected == input, "simulator input differs from golden \(name):\n\(String(decoding: data, as: UTF8.self))",
                sourceLocation: sourceLocation)
    }

    static func makeSimulator() throws -> CombatSimulator {
        let simulator = try CombatSimulator()
        try simulator.loadPinnedCards()
        return simulator
    }

    /// Runs `input` on a simulator of its own, so tests simulate in parallel. (The test runner
    /// has no JIT entitlement, so JavaScriptCore interprets here, several times slower than in the app.)
    static func run(_ input: BattleInput, budget: SimulationBudget = .golden) async throws -> CombatOdds {
        try await makeSimulator().simulate(input: JSONEncoder().encode(input), budget: budget)
    }
}

extension SimulationBudget {
    /// The full 8000 simulations however busy the machine is (no JIT under `swift test`), so the
    /// percentages are stable.
    static let golden = SimulationBudget(simulations: 8000, maxDurationMilliseconds: 600_000, intermediateResults: 200)
}
