import Foundation
import Testing
import TavernEngine

@Suite("Captured discard advisor regressions")
struct AdvisorDiscardReplayTests {
    static let diagnostics = ProcessInfo.processInfo.environment["TAVERN_DISCARD_AUDIT_DIAGNOSTICS"]

    @Test("Archived version-5 advice is unchanged and version 6 checks the observed discard board",
        .enabled(if: diagnostics != nil, "set TAVERN_DISCARD_AUDIT_DIAGNOSTICS to the private diagnostic directory"))
    func capturedDiscardGame() async throws {
        let directory = URL(filePath: Self.diagnostics!)
        let simulator = try CombatSimulator(); try simulator.loadPinnedCards()
        // Include a pair-free Affinity state as well as states where its unknown reward
        // could triple a board minion. No captured requests or player data are committed.
        var restored = 0
        for (turn, index, pendingBuff) in [(6, 1, 0), (8, 0, 12), (8, 5, 32), (9, 1, 88), (11, 0, 128)] {
            let url = directory.appending(path: "game-2034216535-turn-\(turn).json")
            let diagnostic = try JSONDecoder().decode(AdvisorTurnDiagnostic.self, from: Data(contentsOf: url))
            let decisions = try #require(diagnostic.decisions)
            try #require(decisions.indices.contains(index))
            let sample = decisions[index]
            let recorded = sample.displayed
            #expect(recorded.plan.version == 5)
            #expect(recorded.isComplete)
            #expect(recorded.evaluations == 0)
            #expect(sample.request.recruit?.pendingChoice != true)
            #expect(AdviceView.fingerprint(of: sample.request, version: 5) == recorded.fingerprint)
            let simulate: AdvisorEvaluation.Simulate = { input, budget, seed in
                try await simulator.simulate(input, budget: budget, seed: seed)
            }
            let replay = try await recorded.replaying(sample.request, simulate: simulate)
            #expect(replay.advice == recorded.advice)
            #expect(replay.fingerprint == recorded.fingerprint)
            #expect(replay.evaluations == recorded.evaluations)
            #expect(replay.isComplete == recorded.isComplete)

            let calls = AdvisorSynthetic.Calls()
            var currentPlan = AdvisorPlan.live; currentPlan.version = 6
            // A fixed evaluation limit makes this independent of machine speed. This is
            // coverage/projection evidence, not a latency or win-rate assertion.
            let current = try await AdvisorEvaluation.run(sample.request, plan: currentPlan, limit: 12,
                simulate: { input, budget, seed in
                    calls.add(input, budget.simulations, seed)
                    return try await simulator.simulate(input, budget: budget, seed: seed)
                })
            if current.evaluations > 0 { restored += 1 }
            var context = try #require(sample.request.recruit)
            context.evaluationVersion = 6; context.strategicEvaluation = true
            let baseline = RecruitEffects.combatProjection(
                RecruitState(request: sample.request, context: context), context: context)
            if turn == 6 || (turn == 8 && index == 5) {
                #expect(baseline.limitations.contains { $0.contains("Affinity") },
                    "a due random reward can triple and remove minions from these observed pairs")
            }
            if (turn == 8 && index == 0) || turn == 9 || turn == 11 {
                // At turns 9/11 the observed Affinity counter is 2: the raw log shows
                // one decrement, no reward, even with Drakkari on board.
                #expect(baseline.limitations.isEmpty, "pair-free or not-due observed boards are covered")
                #expect(current.evaluations > 0)
            }
            if baseline.limitations.isEmpty {
                let projected = try #require(calls.all.first?.input.playerBoard.board.first)
                let observed = try #require(sample.request.board.first?.entity)
                #expect(projected.entityId == observed.entityId)
                #expect(projected.attack == observed.attack + pendingBuff)
                #expect(projected.health == observed.health + pendingBuff)
            }
            print("DISCARD AUDIT turn=\(turn) oldChecks=\(recorded.evaluations) decision=\(index) newChecks=\(current.evaluations) status=\(current.advice.status)")
            if turn == 8 && index == 5 {
                let continuation = current.advice.suggestions.first?.continuation ?? []
                print("DISCARD SALE AUDIT topPlan=\(continuation.joined(separator: "; "))")
            }
        }
        #expect(restored > 0, "supported states regain combat checks without bypassing random-reward safety")
    }
}
