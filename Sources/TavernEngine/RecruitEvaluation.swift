import BGIntel
import Foundation
import SimulatorRuntime

/// Version 2: strategy proposes short recruit plans; combat checks reject fragile plans against
/// several scenarios. A scenario is evidence/sensitivity testing, never a predicted next board.
public enum RecruitEvaluation {
    public struct Scenario: Sendable {
        public var side: BattleBoard
        public var age: Int
        public var stress: Bool
    }

    public static func scenarios(_ request: AdvisorRequest) -> [Scenario] {
        var observations = request.lobby ?? []
        if let standIn = request.standIn { observations.append(standIn) }
        else if let side = request.preview.input?.opponentBoard, let seen = request.preview.opponentSeenTurn,
                let source = request.preview.opponentSource {
            observations.append(AdvisorLobbyOpponent(playerID: request.preview.opponentPlayerID,
                                                     seenTurn: seen, source: source, side: side))
        }
        var ids: Set<Int> = []
        let recent = observations.sorted { ($0.seenTurn, -$0.playerID) > ($1.seenTurn, -$1.playerID) }.filter {
            ids.insert($0.playerID).inserted && $0.side.player.hpLeft > 0
                && request.preview.bgTurn - $0.seenTurn < AdvisorRequest.staleBoardTurns
        }.prefix(3)
        var result: [Scenario] = []
        for seen in recent {
            let age = max(1, request.preview.bgTurn - seen.seenTurn)
            result.append(Scenario(side: seen.side, age: age, stress: false))
            var stronger = seen.side
            for i in stronger.board.indices {
                stronger.board[i].attack += max(1, stronger.board[i].attack / 4)
                stronger.board[i].health += max(1, stronger.board[i].health / 4)
                stronger.board[i].maxHealth = stronger.board[i].health
            }
            result.append(Scenario(side: stronger, age: age, stress: true))
        }
        return result
    }

    @discardableResult
    public static func run(
        _ request: AdvisorRequest, plan: AdvisorPlan, limit: Int?, shouldContinue: @Sendable () -> Bool,
        simulate: AdvisorEvaluation.Simulate, isolation: isolated (any Actor)? = #isolation,
        report: (AdvisorEvaluation.Progress) -> Void
    ) async throws -> AdvisorEvaluation.Progress {
        guard let context = request.recruit else {
            let done = AdvisorEvaluation.Progress(advice: Advice(status: .noData,
                note: "Recruit card data unavailable; advice withheld"), evaluations: 0, isComplete: true)
            report(done); return done
        }
        try Task.checkCancellation()
        // Search uses a fixed node budget, not wall time, so archived evaluation limits reproduce it.
        let searchTask = Task.detached(priority: .userInitiated) {
            RecruitPlanner.search(request, context: context, shouldContinue: { !Task.isCancelled })
        }
        let search = await withTaskCancellationHandler {
            await searchTask.value
        } onCancel: {
            searchTask.cancel()
        }
        try Task.checkCancellation()
        let scenarios = scenarios(request)
        let plans = [search.baseline] + search.plans
        var results: [String: [Int: CombatTally]] = [:]
        var evaluations = 0
        func progress(_ complete: Bool) -> AdvisorEvaluation.Progress {
            AdvisorEvaluation.Progress(advice: rank(request, search: search, scenarios: scenarios,
                results: results, complete: complete), evaluations: evaluations, isComplete: complete)
        }
        report(progress(false))
        // A full round covers baseline + candidate over exactly the same scenarios. Partial
        // candidates receive no combat advantage and cannot displace a fully checked survival plan.
        for candidate in plans.prefix(9) where candidate.projection.limitations.isEmpty {
            for (index, scenario) in scenarios.enumerated() {
                guard (limit.map { evaluations < $0 } ?? true) && shouldContinue() else {
                    let stopped = progress(false); report(stopped); return stopped
                }
                try Task.checkCancellation()
                var input = candidate.projection.combatInput
                input.opponentBoard = scenario.side
                let odds = try await simulate(input, plan.budget(max(100, plan.simulations)), plan.seed(pass: index))
                try Task.checkCancellation()
                var tally = CombatTally(); tally.add(odds)
                results[candidate.id, default: [:]][index] = tally
                evaluations += 1
                report(progress(false))
            }
        }
        let done = progress(true); report(done); return done
    }

    static func rank(_ request: AdvisorRequest, search: RecruitSearch, scenarios: [Scenario],
                     results: [String: [Int: CombatTally]], complete: Bool) -> Advice {
        let health = request.recruit?.input.playerBoard.player.hpLeft ?? 30
        let baseline = search.baseline
        let baseResults = results[baseline.id] ?? [:]
        struct Ranked {
            var plan: RecruitPlan
            var gain: Double
            var combat: Double
            var checked: Bool
            var riskReduction: Double
        }
        var ranked: [Ranked] = []
        for candidate in search.plans {
            let tallies = results[candidate.id] ?? [:]
            let checked = !scenarios.isEmpty && tallies.count == scenarios.count && baseResults.count == scenarios.count
            var combat = 0.0, reduction = 0.0
            if checked {
                var worst = 0.0
                for i in scenarios.indices {
                    guard let a = tallies[i], let b = baseResults[i] else { continue }
                    reduction += b.lethalRiskPercent - a.lethalRiskPercent
                    worst = min(worst, b.lethalRiskPercent - a.lethalRiskPercent)
                    // Survival is the combat objective; dealt damage and sample win rate are not buying goals.
                    combat += (b.averageDamageTaken - a.averageDamageTaken) * (health <= 15 ? 1.5 : 0.35)
                        + (b.lethalRiskPercent - a.lethalRiskPercent) * (health <= 5 ? 2.0 : health <= 15 ? 0.8 : 0.2)
                }
                combat /= Double(scenarios.count); reduction /= Double(scenarios.count)
                if worst < -10 { continue }
            }
            let sells = candidate.state.steps.filter { $0.kind == .sell }.count
            if sells > 1, candidate.state.board.count < request.board.count, !checked || reduction < 5 { continue }
            let strategy = candidate.value.total - baseline.value.total
            // Reject naked sales that do not finance a useful continuation.
            if candidate.state.steps.last?.kind == .sell { continue }
            if candidate.state.steps.last?.kind == .buy, candidate.state.pendingDiscover == 0 { continue }
            if health <= 5, candidate.state.steps.first?.kind == .level,
               !checked || reduction < 5 { continue }
            // An unresolved effect must never acquire a precise combat benefit from a partial model.
            let score = strategy + combat - Double(candidate.state.steps.count) * 0.05
            guard score > 0.75 else { continue }
            ranked.append(Ranked(plan: candidate, gain: score, combat: combat, checked: checked, riskReduction: reduction))
        }
        ranked.sort {
            if health <= 5, $0.checked != $1.checked { return $0.checked }
            return $0.gain == $1.gain ? $0.plan.id < $1.plan.id : $0.gain > $1.gain
        }
        var suggestions: [AdvisorSuggestion] = []
        var outcomes: Set<RecruitState> = []
        for item in ranked {
            var outcome = item.plan.state
            outcome.steps = []
            guard outcomes.insert(outcome).inserted else { continue }
            guard let first = item.plan.state.steps.first else { continue }
            let delta = item.plan.value.scaling - baseline.value.scaling
            var reason: String
            if item.riskReduction >= 5 { reason = "Safer across the tested combat scenarios" }
            else if first.kind == .darkDiscovery {
                let d = request.recruit?.darkDiscovery
                let tiers = d.map { $0.minTier == $0.maxTier ? "Tier \($0.minTier)" : "Tier \($0.minTier)–\($0.maxTier)" } ?? "a"
                reason = "Discover a \(tiers) minion with a Dark Gift; \(d?.remainingUses ?? 0) uses left. Reassess after choosing"
            }
            else if first.kind == .activate { reason = "Uses your discard engine and its attached rewards" }
            else if first.kind == .roll { reason = "Keep enough gold to buy; reassess after the refresh" }
            else if first.kind == .freeze { reason = "Preserves an unaffordable engine card for next turn" }
            else if delta > 1 { reason = "Improves your scaling engine and its resource supply" }
            else if item.plan.state.tier > request.tier { reason = "Opens a higher tier while preserving the board" }
            else if item.plan.state.steps.contains(where: { $0.kind == .sell }) { reason = "Funds the follow-up without giving up more board value" }
            else { reason = "Improves the board with the gold available this turn" }
            let limitations = Array(Set(search.limitations + item.plan.projection.limitations)).sorted()
            let confidence: AdvisorConfidence = complete && limitations.isEmpty && (health > 5 || item.checked) ? .medium : .low
            if !limitations.isEmpty { reason += " · some effects unmodelled" }
            var suggestion = AdvisorSuggestion(rank: suggestions.count + 1, action: first.action, targets: first.action.targets,
                reason: reason, confidence: confidence, odds: nil, gain: item.gain,
                terms: AdvisorTerms(combat: item.combat + item.plan.value.tempo - baseline.value.tempo, lobby: nil,
                    build: item.plan.value.scaling + item.plan.value.synergy - baseline.value.scaling - baseline.value.synergy,
                    economy: item.plan.value.economy - baseline.value.economy - Double(item.plan.state.steps.count) * 0.05))
            suggestion.continuation = item.plan.state.steps.map(\.title)
            suggestion.limitations = limitations.isEmpty ? nil : limitations
            suggestions.append(suggestion)
            if suggestions.count == 3 { break }
        }
        var notes = ["Plans use your board, scaling and gold"]
        notes.append(scenarios.isEmpty ? "No recent combat evidence" : results.isEmpty ? "Combat checks unavailable for unresolved effects" : "Combat checks use recent boards + stronger stress scenarios")
        if !complete { notes.append("Evaluation incomplete") }
        if !search.limitations.isEmpty { notes.append("Unmodelled effects; no confident recommendation") }
        if suggestions.isEmpty { notes.append("No supported plan clearly improves the position") }
        return Advice(status: suggestions.first?.confidence == .medium ? .recommendation : .noStrongRecommendation,
                      note: notes.joined(separator: " · "), suggestions: suggestions,
                      scored: results.count, candidates: search.plans.count)
    }
}
