import Foundation
import Testing
import TavernEngine

@Suite("Captured Elemental advisor evidence")
struct AdvisorElementalReplayTests {
    static let directory = ProcessInfo.processInfo.environment["TAVERN_ELEMENTAL_AUDIT_DIAGNOSTICS"]

    @Test("Compare the observed Air sale and Clapper shop under policies 9 and 10",
          .enabled(if: directory != nil, "set TAVERN_ELEMENTAL_AUDIT_DIAGNOSTICS for local game evidence"))
    func capturedElementalPlans() async throws {
        let directory = URL(filePath: Self.directory!)
        let simulator = try CombatSimulator(); try simulator.loadPinnedCards()
        for (turn, index) in [(9, 1), (10, 0)] {
            let url = directory.appending(path: "game-904647525-turn-\(turn).json")
            let diagnostic = try JSONDecoder().decode(AdvisorTurnDiagnostic.self, from: Data(contentsOf: url))
            let decisions = try #require(diagnostic.decisions)
            try #require(decisions.indices.contains(index))
            let sample = decisions[index]
            let recorded = sample.displayed
            #expect(recorded.plan.version == 9)
            let replay = try await recorded.replaying(sample.request, simulate: { input, budget, seed in
                try await simulator.simulate(input, budget: budget, seed: seed)
            })
            #expect(replay.advice == recorded.advice)
            #expect(replay.fingerprint == recorded.fingerprint)
            #expect(replay.evaluations == recorded.evaluations)
            print("ELEMENTAL ARCHIVE turn=\(turn) decision=\(index) policy=9 unchanged=\(replay.advice == recorded.advice) checks=\(replay.evaluations)")

            for version in [9, 10] {
                var request = sample.request
                if version == 10, request.recruit?.definitions["BG34_444"] == nil {
                    let build = try #require(request.recruit?.build)
                    let cardsURL = directory.deletingLastPathComponent().appending(path: "CardData/\(build)/cards.json")
                    let cards = try CardDB(build: build, json: Data(contentsOf: cardsURL))
                    let winds = try #require(cards["BG34_444"])
                    request.recruit?.definitions[winds.id] = winds
                    print("ELEMENTAL ENRICHMENT turn=\(turn) policy=10 added=BG34_444 source=localCardData build=\(build)")
                }
                // Match RecruitEvaluation's policy-specific strategy preparation.
                var selectionRequest = request
                if version >= 10 { selectionRequest.recruit?.evaluationVersion = version }
                let selection = AdvisorStrategy.select(selectionRequest)
                var prepared = request
                prepared.builds = selection.map { [$0.build] } ?? []
                prepared.recruit?.evaluationVersion = version
                prepared.recruit?.strategicEvaluation = true
                let context = try #require(prepared.recruit)
                let search = RecruitPlanner.search(prepared, context: context)
                let baseline = search.baseline.value
                print("ELEMENTAL SEARCH turn=\(turn) decision=\(index) policy=\(version) direction=\(selection?.build.name ?? "none") expanded=\(search.expanded) limitations=\(search.limitations)")
                for (rank, plan) in search.plans.prefix(5).enumerated() {
                    let value = plan.value
                    let steps = plan.state.steps.map(\.title).joined(separator: " → ")
                    let hand = plan.state.hand.map { context.definitions[$0.cardID]?.name ?? $0.cardID }
                    print("ELEMENTAL PLAN turn=\(turn) policy=\(version) rank=\(rank + 1) steps=\(steps) finalHand=\(hand) tempo=\(value.tempo - baseline.tempo) scaling=\(value.scaling - baseline.scaling) synergy=\(value.synergy - baseline.synergy) economy=\(value.economy - baseline.economy) limitations=\(plan.projection.limitations)")
                }
                var plan = recorded.plan; plan.version = version
                let unchecked = try await AdvisorEvaluation.run(request, plan: plan, limit: 0,
                    simulate: { _, _, _ in throw CocoaError(.featureUnsupported) })
                #expect(unchecked.evaluations == 0)
                for (rank, suggestion) in unchecked.advice.suggestions.prefix(3).enumerated() {
                    print("ELEMENTAL UNCHECKED turn=\(turn) policy=\(version) rank=\(rank + 1) steps=\((suggestion.continuation ?? []).joined(separator: " → "))")
                }
            }
        }
    }
}
