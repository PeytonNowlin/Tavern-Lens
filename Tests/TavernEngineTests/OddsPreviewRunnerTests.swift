import Foundation
import Testing
import TavernEngine

/// The recruit-phase preview runner on the pinned simulator, with the committed turn-11 input
/// (no private logs needed): debounced board changes, stale runs cancelled, progressive results,
/// "no data" for an unseen opponent, and hypothetical boards scored for the advisor.
///
/// Two boards tell the runs apart: the real turn-11 board loses about 74% (§8.1), and the same
/// combat without the Deities' stats is a likely win (about 78%).
@Suite("Odds preview runner", .timeLimit(.simulationWait))
@MainActor
struct OddsPreviewRunnerTests {
    /// Enough to tell the two boards apart (a few percent of noise), and cheap: every test in the
    /// process shares the simulator's one JavaScript thread.
    static let budget = SimulationBudget(simulations: 800, maxDurationMilliseconds: 600_000, intermediateResults: 50)

    static func losing() throws -> BattleInput { try CombatGoldens.input(CombatGoldens.fullGameTurn11) }

    static func winning() throws -> BattleInput {
        var input = try losing()
        for side in [\BattleInput.playerBoard, \BattleInput.opponentBoard] {
            for index in input[keyPath: side].player.secrets.indices {
                input[keyPath: side].player.secrets[index].tags = nil
                input[keyPath: side].player.secrets[index].scriptDataNum3 = 0
            }
        }
        return input
    }

    static func request(_ input: BattleInput?, turn: Int = 11, opponent: Int = 7) -> OddsPreviewRequest {
        OddsPreviewRequest(
            gameSeed: 1, bgTurn: turn, opponentPlayerID: opponent, opponentSeenTurn: input == nil ? nil : 7,
            opponentSource: input == nil ? nil : .combatStart, input: input
        )
    }

    /// Records every view the runner publishes.
    final class Recorder {
        var views: [OddsPreviewView?] = []
        var odds: [CombatOdds] { views.compactMap { $0?.odds } }
    }

    static func runner(debounce: Duration = .milliseconds(150)) throws -> (OddsPreviewRunner, Recorder) {
        let simulator = try CombatGoldens.makeSimulator()
        let runner = OddsPreviewRunner(simulator: { simulator }, debounce: debounce, budget: budget, replaceAfter: 200)
        let recorder = Recorder()
        runner.onChange = { recorder.views.append($0) }
        return (runner, recorder)
    }

    static func wait(_ runner: OddsPreviewRunner, until done: (OddsPreviewView?) -> Bool) async throws {
        try await waitUntil { done(runner.current) }
    }

    static func waitForFinal(_ runner: OddsPreviewRunner) async throws -> CombatOdds {
        try await wait(runner) { $0?.odds?.isFinal == true && $0?.isUpdating == false }
        return try #require(runner.current?.odds)
    }

    @Test("Board changes within the debounce are simulated once, for the latest board only, after it settles")
    func debounced() async throws {
        let (runner, recorder) = try Self.runner(debounce: .milliseconds(400))
        let clock = ContinuousClock()
        runner.update(Self.request(try Self.winning()))
        try await Task.sleep(for: .milliseconds(250))
        runner.update(Self.request(try Self.losing()))
        let settled = clock.now
        try await Self.wait(runner) { $0?.odds != nil }
        // A lower bound only: the debounce can't end early, however slow the machine.
        #expect(clock.now - settled >= .milliseconds(400), "nothing shown before the board settled")
        let odds = try await Self.waitForFinal(runner)
        #expect(abs(odds.lost - 74) <= 8, "lost \(odds.lost)%")
        // The winning board was replaced before it settled: it was never simulated, so none of its
        // results was ever shown.
        #expect(recorder.odds.allSatisfy { $0.won < 50 }, "\(recorder.odds.map(\.won))")
        #expect(recorder.odds.count >= 2, "partial results before the final one")
    }

    @Test("A board change mid-run cancels the stale run; the old odds stay up, marked updating, until the new ones")
    func staleRunCancelled() async throws {
        let (runner, recorder) = try Self.runner()
        runner.update(Self.request(try Self.winning()))
        // Wait for the winning board's first result, then change the board while it runs.
        try await Self.wait(runner) { $0?.odds != nil }
        #expect(runner.current?.odds?.isFinal == false)
        #expect(try #require(runner.current?.odds).won > 50)
        runner.update(Self.request(try Self.losing()))
        #expect(runner.current?.isUpdating == true, "the previous odds are kept, marked updating")
        #expect(runner.current?.odds?.won ?? 0 > 50)
        try await Self.wait(runner) { $0?.isUpdating == false }
        let odds = try await Self.waitForFinal(runner)
        #expect(abs(odds.lost - 74) <= 8, "lost \(odds.lost)%")
        // The winning run never finished: it was cancelled at its next step.
        #expect(!recorder.odds.contains { $0.isFinal && $0.won > 50 })
        // Once replaced, only the new board's results are shown (at least `replaceAfter` simulations in).
        let replaced = try #require(recorder.views.firstIndex { $0?.isUpdating == false && ($0?.odds?.won ?? 100) < 50 })
        #expect(recorder.views[replaced...].allSatisfy { ($0?.odds?.won ?? 0) < 50 })
        #expect(recorder.views[replaced]?.odds.map { $0.simulations >= 200 || $0.isFinal } == true)
    }

    @Test("Results are shown in order: a partial arriving after a later one, or after the final one, is dropped")
    func ordered() async throws {
        // A scorer that reports a burst of partials from another thread just before it returns, so
        // their hops to the main actor race the final result.
        let simulate: OddsPreviewRunner.Simulate = { _, budget, progress in
            let partials = (1...40).map { step in
                CombatOdds(won: 10, tied: 0, lost: 90, simulations: step * 10, isFinal: false)
            }
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().async {
                    for partial in partials { progress(partial) }
                    done.resume()
                }
            }
            return CombatOdds(won: 10, tied: 0, lost: 90, simulations: budget.simulations, isFinal: true)
        }
        for _ in 0..<5 {
            let runner = OddsPreviewRunner(simulate: simulate, debounce: .zero, budget: Self.budget, refreshInterval: .zero)
            let recorder = Recorder()
            runner.onChange = { recorder.views.append($0) }
            runner.update(Self.request(try Self.losing()))
            try await Self.wait(runner) { $0?.odds?.isFinal == true }
            // Let every hop still queued land.
            for _ in 0..<20 { await Task.yield() }
            try await Task.sleep(for: .milliseconds(50))
            #expect(runner.current?.odds?.isFinal == true, "the final result stays up")
            let shown = recorder.odds.map(\.simulations)
            #expect(shown == shown.sorted() && Set(shown).count == shown.count, "\(shown)")
            #expect(recorder.odds.last?.isFinal == true)
        }
    }

    @Test("The same board again changes nothing; a new turn or opponent starts afresh")
    func sameBoard() async throws {
        let (runner, _) = try Self.runner(debounce: .milliseconds(10))
        let losing = try Self.losing()
        runner.update(Self.request(losing))
        let first = try await Self.waitForFinal(runner)
        runner.update(Self.request(losing))
        #expect(runner.current?.odds == first && runner.current?.isUpdating == false)
        runner.update(Self.request(losing, turn: 12))
        #expect(runner.current?.odds == nil && runner.current?.bgTurn == 12, "no odds carried to another turn")
        runner.cancel()
        #expect(runner.current == nil)
    }

    @Test("An unseen opponent shows no data and runs nothing; leaving recruit clears the preview")
    func noData() async throws {
        let (runner, recorder) = try Self.runner(debounce: .milliseconds(10))
        runner.update(Self.request(try Self.losing()))
        runner.update(Self.request(nil, opponent: 3))
        let view = try #require(runner.current)
        #expect(!view.hasData && view.odds == nil && view.opponentSeenTurn == nil && view.opponentPlayerID == 3)
        // Nothing to wait for: an unseen opponent never starts a run.
        try await Task.sleep(for: .milliseconds(100))
        #expect(runner.current == view, "nothing simulated")
        #expect(recorder.odds.isEmpty)
        runner.update(nil)
        #expect(runner.current == nil)
    }

    @Test("A preview is one per game, BG turn and opponent")
    func identity() throws {
        let view = OddsPreviewView(request: Self.request(nil))
        #expect(view.requestID == "1/11/P7")
        #expect(!view.hasData)
    }

    @Test("Hypothetical boards: the advisor scores a changed board against the same opponent")
    func hypotheticalBoard() async throws {
        let (runner, _) = try Self.runner()
        let request = Self.request(try Self.losing())
        let input = try #require(request.input)
        // Selling the whole board loses for sure.
        let empty = try #require(request.input(withBoard: [], hand: []))
        #expect(empty.opponentBoard == input.opponentBoard && empty.gameState == input.gameState)
        #expect(empty.playerBoard.player == { var p = input.playerBoard.player; p.hand = []; return p }())
        let odds = try await runner.score(empty, budget: Self.budget)
        #expect(odds.lost > 99, "lost \(odds.lost)%")
        // The runner's own preview is untouched.
        #expect(runner.current == nil)
        #expect(Self.request(nil).input(withBoard: []) == nil, "nothing to score without data")
    }
}
