import Foundation
import Testing
import TavernEngine

/// The pinned simulator on the committed combat-start inputs of the captured games. These run
/// without the private logs, and `scripts/update-simulator.sh` runs them before accepting a
/// new simulator version: a bump that moves the odds away from the research fails here.
@Suite("Combat odds goldens (pinned simulator)")
struct CombatOddsGoldenTests {
    /// §8.1: 8.2 / 17.9 / 73.9, 8.8 damage taken (7–13); the real combat lost for 10.
    static func expectFullGameTurn11(_ odds: CombatOdds, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(odds.isFinal && odds.simulations == 8000, "\(odds)", sourceLocation: sourceLocation)
        #expect(abs(odds.lost - 74) <= 3, "lost \(odds.lost)%", sourceLocation: sourceLocation)
        #expect(abs(odds.won - 8) <= 3, "won \(odds.won)%", sourceLocation: sourceLocation)
        #expect(abs(odds.averageDamageLost - 8.8) <= 1, "damage \(odds.averageDamageLost)", sourceLocation: sourceLocation)
        let range = odds.damageLostRange
        #expect(range.map { $0.min <= 10 && 10 <= $0.max } == true, "range \(String(describing: range))",
                sourceLocation: sourceLocation)
        // 16 health left, and the cap is 15: this combat can't be lethal.
        #expect(odds.lostLethal == 0, sourceLocation: sourceLocation)
    }

    /// §8.2: 95.6% loss, 3.2 damage (3–4); the real combat lost for 3.
    static func expectTruncatedGameTurn4(_ odds: CombatOdds, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(odds.isFinal && odds.simulations == 8000, "\(odds)", sourceLocation: sourceLocation)
        #expect(abs(odds.lost - 96) <= 2, "lost \(odds.lost)%", sourceLocation: sourceLocation)
        let range = odds.damageLostRange
        #expect(range.map { $0.min <= 3 && 3 <= $0.max } == true, "range \(String(describing: range))",
                sourceLocation: sourceLocation)
    }

    @Test("Full game turn 11: about a 74% loss, with a range covering the actual 10 damage")
    func fullGameTurn11() async throws {
        let odds = try await CombatGoldens.run(CombatGoldens.input(CombatGoldens.fullGameTurn11))
        Self.expectFullGameTurn11(odds)
    }

    @Test("Truncated game turn 4: about a 96% loss for 3–4")
    func truncatedGameTurn4() async throws {
        let odds = try await CombatGoldens.run(CombatGoldens.input(CombatGoldens.truncatedGameTurn4))
        Self.expectTruncatedGameTurn4(odds)
    }

    @Test("The Deity's health decides the turn-11 combat: without it the loss becomes a likely win (§8.1)")
    func deityMatters() async throws {
        var input = try CombatGoldens.input(CombatGoldens.fullGameTurn11)
        for side in [\BattleInput.playerBoard, \BattleInput.opponentBoard] {
            for index in input[keyPath: side].player.secrets.indices {
                input[keyPath: side].player.secrets[index].tags = nil
                input[keyPath: side].player.secrets[index].scriptDataNum3 = 0
            }
        }
        let odds = try await CombatGoldens.run(input, budget: CombatGoldens.quick)
        #expect(odds.won > 60, "won \(odds.won)%")  // §8.1: 78.0% won
    }

    @Test("A late board's first result comes well within 500 ms and refines in place to the final one")
    func progressive() async throws {
        let simulator = try CombatGoldens.makeSimulator()
        let input = try JSONEncoder().encode(CombatGoldens.input(CombatGoldens.fullGameTurn11))
        let partials = Locked<[CombatOdds]>([])
        let odds = try await simulator.simulate(input: input, budget: .standard) { partial in
            partials.withLock { $0.append(partial) }
        }
        let steps = partials.withLock { $0 }
        // Timed from the simulation's start, since simulations queue on the one JavaScript thread.
        // Under `swift test` JavaScriptCore has no JIT; in the packaged app it takes tens of milliseconds.
        let first = try #require(steps.first)
        #expect(first.elapsedMilliseconds < 500, "first result after \(first.elapsedMilliseconds) ms")
        #expect(steps.count >= 3)
        #expect(steps.map(\.simulations) == steps.map(\.simulations).sorted())
        #expect(steps.allSatisfy { !$0.isFinal })
        #expect(odds.isFinal && odds.simulations >= steps.last?.simulations ?? 0)
        #expect(odds.elapsedMilliseconds <= SimulationBudget.standard.maxDurationMilliseconds + 250)
    }

    @Test("Cancelling stops a simulation at its next step")
    func cancel() async throws {
        let simulator = try CombatGoldens.makeSimulator()
        let input = try JSONEncoder().encode(CombatGoldens.input(CombatGoldens.fullGameTurn11))
        let task = Task {
            try await simulator.simulate(input: input, budget: CombatGoldens.slow)
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        // The simulator is free again at once.
        let odds = try await simulator.simulate(
            input: input, budget: SimulationBudget(simulations: 400, maxDurationMilliseconds: 5000, intermediateResults: 200)
        )
        #expect(odds.isFinal)
    }

    @Test("The bundle is the pinned simulator, and its card data loads")
    func pinned() throws {
        let package = try JSONDecoder().decode(
            PackageJSON.self, from: Data(contentsOf: CombatGoldens.repositoryRoot.appending(path: "Tools/Simulator/package.json"))
        )
        let pin = try #require(SimulatorResources.pin)
        #expect(pin.simulator == package.dependencies["@firestone-hs/simulate-bgs-battle"])
        #expect(pin.referenceData == package.dependencies["@firestone-hs/reference-data"])
        #expect(pin.esbuild == package.devDependencies["esbuild"])
        let simulator = try CombatGoldens.makeSimulator()
        #expect(simulator.versions == ["simulator": pin.simulator, "referenceData": pin.referenceData])
        #expect(simulator.isReady)
    }

    private struct PackageJSON: Decodable {
        var dependencies: [String: String]
        var devDependencies: [String: String]
    }
}

extension CombatGoldens {
    /// Long enough to still be running when cancelled.
    static let slow = SimulationBudget(simulations: 1_000_000, maxDurationMilliseconds: 30_000, intermediateResults: 200)
    /// Enough to tell a likely win from a likely loss.
    static let quick = SimulationBudget(simulations: 1500, maxDurationMilliseconds: 600_000, intermediateResults: 500)

    static let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

/// A value shared with a `@Sendable` callback.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func withLock<R>(_ body: (inout Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
