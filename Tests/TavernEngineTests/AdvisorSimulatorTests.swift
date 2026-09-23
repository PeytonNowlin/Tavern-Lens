import Foundation
import Testing
import TavernEngine

/// The advisor on the pinned simulator, fixture-free: seeded simulations reproduce exactly, a
/// committed recruit state (turn 11 of the full game, against the opponent's actual board) scores
/// to its golden advice, and the advisor never holds up a combat's odds.
@Suite("Advisor on the simulator")
struct AdvisorSimulatorTests {
    /// Turn 11 of the full game as the shop opened (10 gold), with the next opponent's board as it
    /// really was at that combat (about a 74% loss), recorded by `AdvisorFixtureTests`.
    static let turn11 = "full-game-turn-11-actual-opponent"

    static func request() throws -> AdvisorRequest {
        try AdvisorFixture.load(AdvisorRequest.self, golden: "\(turn11).request")
    }

    static func stripTiming(_ odds: CombatOdds) -> CombatOdds {
        var odds = odds
        odds.elapsedMilliseconds = 0
        return odds
    }

    @Test("A seeded simulation gives the same result every time, on any simulator; another seed doesn't")
    func seeded() async throws {
        let input = try CombatGoldens.input(CombatGoldens.fullGameTurn11)
        let budget = SimulationBudget(simulations: 300, maxDurationMilliseconds: 600_000, intermediateResults: 50)
        let first = try CombatGoldens.makeSimulator()
        let a = try await first.simulate(input, budget: budget, seed: 7)
        _ = try await first.simulate(input, budget: budget)  // unseeded in between
        let b = try await first.simulate(input, budget: budget, seed: 7)
        let c = try await CombatGoldens.makeSimulator().simulate(input, budget: budget, seed: 7)
        #expect(Self.stripTiming(a) == Self.stripTiming(b) && Self.stripTiming(b) == Self.stripTiming(c))
        #expect(a.simulations == 300)
        var differs = false
        for seed in UInt32(8)...12 where Self.stripTiming(try await first.simulate(input, budget: budget, seed: seed)) != Self.stripTiming(a) {
            differs = true
            break
        }
        #expect(differs, "the seed changes the dice")
    }

    @Test("The committed turn-11 state scores to its golden advice, the same every time")
    func golden() async throws {
        let request = try Self.request()
        let simulate = try AdvisorFixture.simulate()
        var reports: [AdvisorEvaluation.Progress] = []
        let done = try await AdvisorEvaluation.run(request, plan: AdvisorFixture.plan, simulate: simulate) { reports.append($0) }
        #expect(done.isComplete)
        let view = AdviceView(request: request, plan: AdvisorFixture.plan, advice: done.advice,
                              evaluations: done.evaluations, isComplete: true)
        try AdvisorFixture.verify(view, golden: "\(Self.turn11).advice")

        // Against their real board the current board loses most of the time: something should help.
        let baseline = try #require(done.advice.baseline)
        #expect(baseline.lost > 50, "baseline \(baseline)")
        for suggestion in done.advice.suggestions { #expect(!suggestion.reason.isEmpty) }

        // Partway, as a bookmark would have caught it: replaying that many evaluations gives the same advice.
        let partway = try #require(reports.first { $0.evaluations == done.evaluations / 2 })
        let shown = AdviceView(request: request, plan: AdvisorFixture.plan, advice: partway.advice, evaluations: partway.evaluations)
        let replayed = try await shown.replaying(request, simulate: try AdvisorFixture.simulate())
        #expect(replayed.advice == shown.advice)
    }

    @Test("A combat's odds aren't held up by the advisor: they wait at most one evaluation, and cancel stops it")
    @MainActor
    func combatFirst() async throws {
        let request = try Self.request()
        let simulator = try CombatGoldens.makeSimulator()
        // Every evaluation the advisor asks for, and whether it ran to the end.
        let log = EvaluationLog()
        let simulate: AdvisorEvaluation.Simulate = { input, budget, seed in
            log.started()
            let odds = try await simulator.simulate(input, budget: budget, seed: seed)
            log.finished()
            return odds
        }
        // A plan far too big to finish during the test.
        let plan = AdvisorPlan(seed: 1, simulations: 300, refineSimulations: 5000, refinedGroups: 6)
        // Every evaluation shown (no throttle), so `current` counts the finished ones.
        let runner = AdvisorRunner(simulate: simulate, plan: plan, debounce: .milliseconds(1), timeBudget: .seconds(600),
                                   refreshInterval: .zero)
        runner.update(request)
        // Generous: in the full suite other tests share the simulator's one thread and the main actor.
        let deadline = ContinuousClock.now + .seconds(600)
        while (runner.current?.evaluations ?? 0) < 2 {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }

        // A combat starts: the app cancels the advisor and simulates the combat on the same simulator.
        let clock = ContinuousClock()
        let start = clock.now
        let scored = try #require(runner.current?.evaluations)
        runner.cancel()
        let combat = try CombatGoldens.input(CombatGoldens.fullGameTurn11)
        let first = FirstResult()
        _ = try await simulator.simulate(combat, budget: .init(simulations: 200, maxDurationMilliseconds: 600_000, intermediateResults: 50)) { _ in
            first.mark(clock.now)
        }
        let waited = try #require(first.at) - start
        // The advisor asks for nothing more once cancelled, and its evaluation in flight stops at its
        // next step: the combat waits for at most that (300 simulations of a late board are a few
        // seconds interpreted under `swift test`, a tenth of that in the app; the plan is minutes).
        #expect(waited < .seconds(60), "first combat result after \(waited)")
        #expect(runner.current == nil)
        try await Task.sleep(for: .milliseconds(500))
        #expect(log.finishedCount == scored, "the evaluation in flight was cut short, and none finished after")
        #expect(log.startedCount <= scored + 1, "nothing new was asked for after the cancel")
    }

    final class EvaluationLog: @unchecked Sendable {
        private let lock = NSLock()
        private var starts = 0, finishes = 0
        func started() { lock.withLock { starts += 1 } }
        func finished() { lock.withLock { finishes += 1 } }
        var startedCount: Int { lock.withLock { starts } }
        var finishedCount: Int { lock.withLock { finishes } }
    }

    final class FirstResult: @unchecked Sendable {
        private let lock = NSLock()
        private var instant: ContinuousClock.Instant?
        func mark(_ now: ContinuousClock.Instant) { lock.withLock { if instant == nil { instant = now } } }
        var at: ContinuousClock.Instant? { lock.withLock { instant } }
    }
}
