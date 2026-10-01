import Foundation
import Testing
import TavernEngine

@Suite("Logged advisor regressions")
struct AdvisorLogRegressionTests {
    typealias S = AdvisorSynthetic

    @Test("An unchecked level plan is withheld at eleven health, including after another action")
    func uncheckedLevel() async throws {
        var request = try RecruitPlannerTests.request(board: [S.boardMinion(1, "body", attack: 2, health: 2)],
            shop: [S.shopMinion(2, attack: 8, health: 8, cardID: "upgrade")], gold: 10)
        request.levelCost = 7
        request.recruit?.input.playerBoard.player.hpLeft = 11
        request.recruit?.input.playerBoard.player.questRewards = ["UNKNOWN_REWARD"]
        let result = try await AdvisorEvaluation.run(request, plan: .live,
            simulate: S.simulate(.init(baseline: 0)))
        #expect(result.evaluations == 0)
        #expect(result.advice.suggestions.allSatisfy {
            $0.continuation?.contains(where: { $0.hasPrefix("Level to") }) != true
        })
        var old = AdvisorPlan.live; old.version = 3
        let archived = try await AdvisorEvaluation.run(request, plan: old,
            simulate: S.simulate(.init(baseline: 0)))
        #expect(archived.advice.suggestions.contains {
            $0.continuation?.contains(where: { $0.hasPrefix("Level to") }) == true
        })
    }

    @Test("Combat-only and next-turn trinkets do not block current recruit combat checks",
        arguments: [
            ("BG32_MagicItem_363", "Whenever a friendly Dragon attacks, give it Divine Shield. (3 times per combat.)"),
            ("BG32_MagicItem_860t", "Avenge (7): Summon two 2/2 Beetles. Give them Taunt."),
            ("BG30_MagicItem_430", "Get a random Battlecry minion. At the start of each turn, get another.")
        ])
    func trinketChecks(_ effect: (String, String)) async throws {
        var request = try RecruitPlannerTests.request(board: [S.boardMinion(1, "body", attack: 2, health: 2)],
            shop: [S.shopMinion(2, attack: 8, health: 8, cardID: "upgrade")])
        let trinket = try JSONDecoder().decode(BattleTrinket.self,
            from: Data("{\"cardId\":\"\(effect.0)\",\"entityId\":100,\"scriptDataNum1\":3,\"scriptDataNum2\":0,\"scriptDataNum6\":0}".utf8))
        request.recruit?.input.playerBoard.player.trinkets = [trinket]
        var definition = Card(id: effect.0, dbfId: 100, name: effect.0); definition.text = effect.1
        request.recruit?.definitions[effect.0] = definition
        let result = try await AdvisorEvaluation.run(request, plan: .live,
            simulate: S.simulate(.init(baseline: 0)))
        #expect(result.evaluations > 0)
        #expect(result.advice.suggestions.allSatisfy {
            $0.limitations?.contains(where: { $0.contains("Unmodelled trinket") }) != true
        })
        var old = AdvisorPlan.live; old.version = 3
        let archived = try await AdvisorEvaluation.run(request, plan: old,
            simulate: S.simulate(.init(baseline: 0)))
        #expect(archived.advice.suggestions.contains {
            $0.limitations?.contains(where: { $0.contains("Unmodelled trinket") }) == true
        })
        #expect(result.evaluations > archived.evaluations)
        request.recruit?.definitions[effect.0]?.text = "At the end of your turn, transform your minions randomly."
        let changed = try await AdvisorEvaluation.run(request, plan: .live,
            simulate: S.simulate(.init(baseline: 0)))
        #expect(changed.evaluations == 0, "a reused ID with changed behavior stays unsupported")
    }

    @Test("A checked supported plan is not poisoned by an unused unknown shop battlecry")
    func alternativeCoverage() async throws {
        let request = try RecruitPlannerTests.request(board: [S.boardMinion(1, "body", attack: 2, health: 2)],
            shop: [S.shopMinion(2, attack: 8, health: 8, cardID: "upgrade"),
                   S.shopMinion(3, attack: 20, health: 20, cardID: "unknown"),
                   S.shopMinion(4, attack: 7, health: 7, cardID: "backup")],
            texts: ["unknown": "Battlecry: Gain a random Bonus Keyword."])
        let result = try await AdvisorEvaluation.run(request, plan: .live,
            simulate: S.simulate(.init(baseline: 0)))
        #expect(result.advice.status == .recommendation)
        #expect(result.advice.suggestions.first?.confidence == .medium)
        #expect(result.advice.note?.contains("alternative") == true)
        #expect(result.advice.suggestions.first?.limitations?.contains(where: { $0.contains("unknown") }) != true)
        let presentation = AdvisorPresentation(advice: AdviceView(request: request, plan: .live,
            advice: result.advice, evaluations: result.evaluations, isComplete: result.isComplete), request: request)
        #expect(presentation.primary != nil)
        #expect(presentation.caveat?.contains("alternative") == true)
        var old = AdvisorPlan.live; old.version = 3
        let archived = try await AdvisorEvaluation.run(request, plan: old,
            simulate: S.simulate(.init(baseline: 0)))
        #expect(archived.advice.status == .noStrongRecommendation)
        let partial = try await AdvisorEvaluation.run(request, plan: .live, limit: 4,
            simulate: S.simulate(.init(baseline: 0)))
        #expect(!partial.isComplete)
        #expect(partial.advice.suggestions.first?.confidence == .medium)
        #expect(partial.advice.note?.contains("Evaluation incomplete") == true)
        let unfinishedPlan = try await AdvisorEvaluation.run(request, plan: .live, limit: 3,
            simulate: S.simulate(.init(baseline: 0)))
        #expect(unfinishedPlan.advice.suggestions.allSatisfy { $0.confidence == .low })
    }

    @Test("Steady Growth applies only its pending increment, without repeating historical buffs")
    func steadyGrowth() async throws {
        var card = S.boardMinion(1, "body", attack: 20, health: 30)
        card.entity.enchantments = try JSONDecoder().decode([BattleEnchantment].self, from: Data("""
            [{"cardId":"BG36_MidGameEffect_000t51e","originEntityId":101,"timing":0,
              "tagScriptDataNum1":3,"tagScriptDataNum2":4},
             {"cardId":"BG36_MidGameEffect_000t51e2","originEntityId":102,"timing":0,
              "tagScriptDataNum1":15,"tagScriptDataNum2":18}]
            """.utf8))
        var request = try RecruitPlannerTests.request(board: [card],
            shop: [S.shopMinion(2, attack: 8, health: 8, cardID: "upgrade")])
        for (id, text) in [("BG36_MidGameEffect_000t51e", "At the end of your turn, gain +0/+0."),
                           ("BG36_MidGameEffect_000t51e2", "+0/+0.")] {
            var definition = Card(id: id, dbfId: 100, name: "Steady Growth"); definition.text = text
            request.recruit?.definitions[id] = definition
        }
        let calls = S.Calls()
        let result = try await AdvisorEvaluation.run(request, plan: .live,
            simulate: S.simulate(.init(baseline: 0), calls: calls))
        #expect(result.evaluations > 0)
        #expect(calls.all.first?.input.playerBoard.board.first?.attack == 23)
        #expect(calls.all.first?.input.playerBoard.board.first?.health == 34)
        #expect(request.board.first?.entity.attack == 20)
        let repeatTrinket = try JSONDecoder().decode(BattleTrinket.self,
            from: Data("{\"cardId\":\"repeat\",\"entityId\":103,\"scriptDataNum1\":0,\"scriptDataNum2\":0,\"scriptDataNum6\":0}".utf8))
        var repeatDefinition = Card(id: "repeat", dbfId: 103, name: "Extra end of turn")
        repeatDefinition.text = "Your end of turn effects trigger an extra time."
        request.recruit?.definitions["repeat"] = repeatDefinition
        request.recruit?.input.playerBoard.player.trinkets = [repeatTrinket]
        let repeatedCalls = S.Calls()
        _ = try await AdvisorEvaluation.run(request, plan: .live,
            simulate: S.simulate(.init(baseline: 0), calls: repeatedCalls))
        #expect(repeatedCalls.all.first?.input.playerBoard.board.first?.attack == 26)
        #expect(repeatedCalls.all.first?.input.playerBoard.board.first?.health == 38)
        request.recruit?.input.playerBoard.player.trinkets = []
        var old = AdvisorPlan.live; old.version = 3
        let archived = try await AdvisorEvaluation.run(request, plan: old,
            simulate: S.simulate(.init(baseline: 0)))
        #expect(archived.evaluations == 0)
        request.board[0].entity.enchantments[0].tagScriptDataNum1 = nil
        let unknown = try await AdvisorEvaluation.run(request, plan: .live,
            simulate: S.simulate(.init(baseline: 0)))
        #expect(unknown.evaluations == 0, "missing pending increment must not be guessed")
    }

    @Test("Unknown alternatives stay uncertain when the supported plan has no combat evidence")
    func uncheckedAlternative() async throws {
        var request = try RecruitPlannerTests.request(shop: [S.shopMinion(1, attack: 8, health: 8, cardID: "upgrade"),
            S.shopMinion(2, attack: 20, health: 20, cardID: "unknown")],
            texts: ["unknown": "Battlecry: Gain a random Bonus Keyword."])
        request.preview.input = nil; request.preview.opponentSeenTurn = nil
        let result = try await AdvisorEvaluation.run(request, plan: .live,
            simulate: S.simulate(.init(baseline: 0)))
        #expect(result.evaluations == 0)
        #expect(result.advice.status == .noStrongRecommendation)
        #expect(result.advice.suggestions.allSatisfy { $0.confidence == .low })
    }

    @Test("Low-health leveling requires checked scenarios without increasing lethal risk")
    func checkedLevel() async throws {
        var request = try RecruitPlannerTests.request(board: [S.boardMinion(1, "body", attack: 2, health: 2)], gold: 10)
        request.tier = 4; request.recruit?.input.playerBoard.player.tavernTier = 4
        request.levelCost = 7; request.recruit?.input.playerBoard.player.hpLeft = 11
        let safe = try await AdvisorEvaluation.run(request, plan: .live,
            simulate: S.simulate(.init(baseline: 0)))
        #expect(safe.advice.suggestions.contains { $0.continuation?.contains("Level to tier \(request.tier + 1)") == true })
        let tier = request.tier
        let risky = try await AdvisorEvaluation.run(request, plan: .live, simulate: { input, budget, _ in
            let risk = input.playerBoard.player.tavernTier > tier ? 5.0 : 0.0
            return CombatOdds(won: 50, tied: 0, lost: 50, lostLethal: risk, averageDamageLost: 8,
                simulations: budget.simulations, isFinal: true)
        })
        #expect(risky.advice.suggestions.allSatisfy { $0.continuation?.contains(where: { $0.hasPrefix("Level to") }) != true })
    }

    @Test("Old request fingerprints ignore the new evaluation-policy field")
    func archivedFingerprint() throws {
        var request = try RecruitPlannerTests.request()
        let old = AdviceView.fingerprint(of: request, version: 3)
        request.recruit?.evaluationVersion = AdvisorPlan.live.version
        #expect(AdviceView.fingerprint(of: request, version: 3) == old)
        #expect(AdviceView.fingerprint(of: request) != old)
    }

    static let diagnostics = ProcessInfo.processInfo.environment["TAVERN_LOG_AUDIT_DIAGNOSTICS"]

    @Test("Captured decisions from all three games replay under their recorded policy",
        .enabled(if: diagnostics != nil, "set TAVERN_LOG_AUDIT_DIAGNOSTICS to the private diagnostic directory"))
    func capturedGames() async throws {
        let cases = AdvisorCase.savedDiagnostics(in: URL(filePath: Self.diagnostics!))
        let simulator = try CombatSimulator(); try simulator.loadPinnedCards()
        let simulate: AdvisorEvaluation.Simulate = { input, budget, seed in
            try await simulator.simulate(input, budget: budget, seed: seed)
        }
        var restored = 0
        for seed in [670219605, 483422699, 1179245919] {
            for turn in [6, 9, 11] {
                let sample = try #require(cases.first {
                    $0.name.hasPrefix("game-\(seed)-turn-\(turn)-decision-")
                        && $0.recorded?.advice.status != .noData && $0.recorded?.advice.status != .thinking
                        && $0.request.recruit?.pendingChoice != true
                })
                let recorded = try #require(sample.recorded)
                #expect(recorded.plan.version == 3)
                let replay = try await recorded.replaying(sample.request, simulate: simulate)
                #expect(replay.advice == recorded.advice)
                let start = ContinuousClock.now
                let deadline = start + .seconds(5)
                let current = try await AdvisorEvaluation.run(sample.request, plan: .live,
                    shouldContinue: { ContinuousClock.now < deadline }, simulate: simulate)
                if recorded.evaluations == 0 && current.evaluations > 0 { restored += 1 }
                if sample.request.recruit!.input.playerBoard.player.hpLeft <= 15 && current.evaluations == 0 {
                    #expect(current.advice.suggestions.allSatisfy {
                        $0.continuation?.contains(where: { $0.hasPrefix("Level to") }) != true
                    })
                }
                print("AUDIT game=\(seed) turn=\(turn) oldChecks=\(recorded.evaluations) newChecks=\(current.evaluations) status=\(current.advice.status) elapsed=\(start.duration(to: .now))")
            }
        }
        #expect(restored > 0, "observed supported mechanics restore at least one previously blocked combat evaluation")
    }
}
