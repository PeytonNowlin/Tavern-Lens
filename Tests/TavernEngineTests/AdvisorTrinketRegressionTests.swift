import Foundation
import Testing
import TavernEngine

@Suite("Observed trinket coverage regressions")
struct AdvisorTrinketRegressionTests {
    typealias S = AdvisorSynthetic
    static let phylactery = "BG30_MagicItem_700"
    static let portrait = "BG30_MagicItem_876"
    static let phylacteryText = "Discover a Deathrattle minion. Your first Deathrattle each combat triggers an extra time."
    static let portraitText = "Get a Faceless Manipulator."

    static func trinket(_ id: String, trigger: Int? = nil) throws -> BattleTrinket {
        var object: [String: Any] = ["cardId": id, "entityId": 100, "scriptDataNum1": 0,
                                     "scriptDataNum2": 0, "scriptDataNum6": 1]
        if let trigger { object["tags"] = ["32": trigger] }
        return try JSONDecoder().decode(BattleTrinket.self, from: JSONSerialization.data(withJSONObject: object))
    }

    static func tags(_ trinket: BattleTrinket) throws -> [String: Int]? {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(trinket)) as? [String: Any]
        return object?["tags"] as? [String: Int]
    }

    @Test("Observed trinket trigger state reaches simulator input, including consumed zero", arguments: [0, 1])
    func observedTrigger(_ trigger: Int) throws {
        let log = CombatInputSyntheticTests.combat(local: { log in
            log.trinket(348, Self.phylactery, controller: CombatInputSyntheticTests.local, slot: 1)
            log.tag(348, "TRIGGER_VISUAL", "\(trigger)")
        })
        let input = try CombatInputSyntheticTests.request(log).input
        let trinket = try #require(input.playerBoard.player.trinkets.first)
        #expect(try Self.tags(trinket)?["32"] == trigger)
    }

    @Test("Old recordings and unobserved trinket tags stay absent instead of inventing a trigger")
    func legacyAndMissingTrigger() throws {
        let old = try Self.trinket(Self.phylactery)
        #expect(try Self.tags(old) == nil)
        let log = CombatInputSyntheticTests.combat(local: { log in
            log.trinket(348, Self.phylactery, controller: CombatInputSyntheticTests.local, slot: 1)
        })
        let input = try CombatInputSyntheticTests.request(log).input
        #expect(try Self.tags(#require(input.playerBoard.player.trinkets.first)) == nil)
    }

    @Test("Pinned combat consumes the observed Phylactery trigger rather than treating it as script data")
    func phylacteryCombat() async throws {
        var input = try RecruitPlannerTests.request().recruit!.input
        // Reborn has already been spent. Both the Summoner and its Knight token are in the
        // pinned card bundle; the legacy Harvest Golem token is not.
        input.playerBoard.board = [S.minion(1, "BG25_009", attack: 8, health: 1)]
        input.opponentBoard.player = input.playerBoard.player
        input.opponentBoard.player.entityId = 200
        input.opponentBoard.board = [S.minion(2, "BG_CFM_315", attack: 9, health: 9)]
        let budget = SimulationBudget(simulations: 20, maxDurationMilliseconds: 600_000, intermediateResults: 20)
        input.playerBoard.player.trinkets = [try Self.trinket(Self.phylactery, trigger: 1)]
        let active = try await CombatGoldens.run(input, budget: budget)
        input.playerBoard.player.trinkets = [try Self.trinket(Self.phylactery, trigger: 0)]
        let consumed = try await CombatGoldens.run(input, budget: budget)
        #expect(active.won == 100, "the second Eternal Knight survives")
        #expect(consumed.tied == 100, "without the extra trigger the only token trades")
    }

    @Test("Observed Phylactery and resolved Portrait permit supported recruit plans", arguments: [phylactery, portrait])
    func supportedTrinket(_ id: String) async throws {
        var request = try RecruitPlannerTests.request(board: [S.boardMinion(1, "body", attack: 2, health: 2)],
            shop: [S.shopMinion(2, attack: 8, health: 8, cardID: "upgrade")])
        request.recruit?.input.playerBoard.player.trinkets = [try Self.trinket(id, trigger: id == Self.phylactery ? 1 : nil)]
        var definition = Card(id: id, dbfId: 100, name: id)
        definition.text = id == Self.phylactery ? Self.phylacteryText : Self.portraitText
        request.recruit?.definitions[id] = definition
        let calls = S.Calls()
        let live = try await AdvisorEvaluation.run(request, plan: .live, simulate: S.simulate(.init(baseline: 0), calls: calls))
        #expect(live.evaluations > 0)
        #expect(!live.advice.suggestions.isEmpty)
        #expect(live.advice.suggestions.allSatisfy { $0.limitations?.contains(where: { $0.contains("Unmodelled trinket") }) != true })
        #expect(calls.all.allSatisfy { $0.input.playerBoard.player.trinkets == request.recruit?.input.playerBoard.player.trinkets })
        #expect(calls.all.allSatisfy { $0.input.playerBoard.player.hand.isEmpty }, "one-time trinket rewards are not granted again")
        var old = AdvisorPlan.live; old.version = 6
        let archived = try await AdvisorEvaluation.run(request, plan: old, simulate: S.simulate(.init(baseline: 0)))
        #expect(archived.advice.suggestions.contains { $0.limitations?.contains(where: { $0.contains("Unmodelled trinket") }) == true })

        request.recruit?.definitions[id]?.text = "At the end of your turn, transform your minions randomly."
        let changed = try await AdvisorEvaluation.run(request, plan: .live, simulate: S.simulate(.init(baseline: 0)))
        #expect(changed.evaluations == 0, "changed text stays unsupported")
    }

    @Test("Missing Phylactery trigger state and Faceless copying stay explicitly unmodelled")
    func missingStateAndCopy() throws {
        let faceless = S.boardMinion(3, "BG_EX1_564", attack: 3, health: 3)
        var request = try RecruitPlannerTests.request(board: [S.boardMinion(1, "body", attack: 2, health: 2)],
            hand: [faceless], texts: [faceless.cardID: "Battlecry: Choose a minion and become a copy of it."])
        request.recruit?.evaluationVersion = 7
        request.recruit?.input.playerBoard.player.trinkets = [try Self.trinket(Self.phylactery)]
        var definition = Card(id: Self.phylactery, dbfId: 100, name: "Deathly Phylactery")
        definition.text = Self.phylacteryText
        request.recruit?.definitions[definition.id] = definition
        let context = request.recruit!
        let result = RecruitPlanner.search(request, context: context)
        #expect(result.limitations.contains { $0.contains("Unmodelled trinket: Deathly Phylactery") })
        #expect(result.baseline.projection.limitations.contains { $0.contains("Unmodelled trinket: Deathly Phylactery") })
        #expect(result.limitations.contains { $0.contains("Unmodelled play") })
        #expect(result.plans.allSatisfy { !$0.state.board.contains(where: { $0.entity.entityId == faceless.entity.entityId }) })
    }
}
