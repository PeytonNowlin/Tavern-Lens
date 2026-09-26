import Foundation
import Testing
import TavernEngine

@Suite("Strategic recruit advice")
struct StrategicAdvisorTests {
    @Test("An offered core opens an attainable direction before build detection")
    func offeredDirection() async throws {
        var request = try RecruitPlannerTests.request(shop: [AdvisorSynthetic.shopMinion(1, attack: 4, health: 4, cardID: "engine")])
        request.strategyCatalog = [AdvisorBuild(id: "growth", name: "Growth engine", share: 1,
                                               core: ["engine", "payoff"], addons: [], coreTiers: ["engine": 3, "payoff": 4])]
        let result = try await AdvisorEvaluation.run(request, plan: .live,
                                                     simulate: AdvisorSynthetic.simulate(.init(baseline: 0)))
        if let path = ProcessInfo.processInfo.environment["TAVERN_ADVISOR_PREVIEW_JSON"] {
            let view = AdviceView(request: request, plan: .live, advice: result.advice, evaluations: result.evaluations, isComplete: true)
            try JSONEncoder().encode(view).write(to: URL(filePath: path))
        }
        #expect(result.advice.strategy?.buildID == "growth")
        #expect(result.advice.strategy?.committed == false)
        #expect(result.advice.strategy?.missing == ["payoff"])
        #expect(result.advice.suggestions.first?.continuation?.contains { $0.contains("engine") } == true)
    }
    @Test("Engine offers the catalog before detecting an owned build")
    func catalogBeforeDetection() throws {
        var log = BuildSyntheticTests.recruiting(board: [])
        log.localTag("NEXT_OPPONENT_PLAYER_ID", "3")
        log.endTaskList()
        var engine = TavernEngine(builds: BuildSyntheticTests.catalog)
        for line in log.lines { engine.ingest(line) }
        let request = try #require(engine.advisorRequest)
        #expect(request.builds?.isEmpty != false)
        #expect(request.strategyCatalog?.isEmpty == false)
        #expect(request.strategyCatalog?.contains { $0.id == "beast_lobster" } == true)
    }
    @Test("Resolved choices retract obsolete instructions immediately")
    @MainActor func choiceFreshness() async throws {
        var request = try RecruitPlannerTests.request()
        request.recruit?.pendingChoice = true
        let runner = AdvisorRunner(simulate: AdvisorSynthetic.simulate(.init(baseline: 0)),
                                   debounce: .milliseconds(1))
        runner.update(request)
        try await waitUntil { runner.current?.isComplete == true }
        #expect(runner.current?.advice.status == .noData)
        request.recruit?.pendingChoice = false
        runner.update(request)
        #expect(runner.current?.advice.note?.contains("Finish the current choice") != true)
        #expect(runner.current?.fingerprint == AdviceView.fingerprint(of: request))
        runner.cancel()
    }
    @Test("Shared support cards do not satisfy an engine's commitment requirements")
    func commitmentRoles() async throws {
        var request = try RecruitPlannerTests.request(board: [
            AdvisorSynthetic.boardMinion(1, "support", attack: 2, health: 2),
            AdvisorSynthetic.boardMinion(2, "support2", attack: 2, health: 2)])
        var build = AdvisorBuild(id: "growth", name: "Growth", share: 1,
                                 core: ["support", "support2", "engine"], addons: [])
        build.requirements = [BuildRequirement(role: "scaling engine", anyOf: ["engine"])]
        request.strategyCatalog = [build]
        let result = try await AdvisorEvaluation.run(request, plan: .live,
                                                     simulate: AdvisorSynthetic.simulate(.init(baseline: 0)))
        #expect(result.advice.strategy?.committed == false)
        #expect(result.advice.strategy?.missing == ["engine"])
    }
    @Test("An already granted economy reward permits combat checks, while old evaluations stay reproducible")
    func economyQuest() async throws {
        var request = try RecruitPlannerTests.request(shop: [AdvisorSynthetic.shopMinion(1, attack: 5, health: 5)])
        request.recruit?.input.playerBoard.player.questRewards = ["BG33_Reward_012"]
        let current = try await AdvisorEvaluation.run(request, plan: .live,
                                                      simulate: AdvisorSynthetic.simulate(.init(baseline: 0)))
        #expect(current.evaluations > 0)
        var old = AdvisorPlan.live; old.version = 2
        let archived = try await AdvisorEvaluation.run(request, plan: old,
                                                       simulate: AdvisorSynthetic.simulate(.init(baseline: 0)))
        #expect(archived.evaluations == 0)
        request.recruit?.input.playerBoard.player.questRewards = ["UNKNOWN_REWARD"]
        let unknown = try await AdvisorEvaluation.run(request, plan: .live,
                                                      simulate: AdvisorSynthetic.simulate(.init(baseline: 0)))
        #expect(unknown.evaluations == 0)
    }
    @Test("Seasonal choice guidance is part of advisor output and suspends recruit actions")
    func seasonalChoice() async throws {
        var request = try RecruitPlannerTests.request()
        request.recruit?.pendingChoice = true
        request.choice = AdvisorChoice(entityID: 11, cardID: "trinket", name: "Engine trinket", cost: 2,
                                       reason: "Supplies your discard engine", confidence: .low)
        let result = try await AdvisorEvaluation.run(request, plan: .live,
                                                     simulate: AdvisorSynthetic.simulate(.init(baseline: 0)))
        #expect(result.advice.choice?.entityID == 11)
        #expect(result.advice.suggestions.isEmpty)
        #expect(result.evaluations == 0)
    }
    @Test("Evaluation separates operational coverage from human-reviewed decision quality")
    func qualityReport() async throws {
        let request = try RecruitPlannerTests.request(shop: [AdvisorSynthetic.shopMinion(1, attack: 5, health: 5)])
        let report = try await AdvisorQualityEvaluation.run([AdvisorQualityCase(name: "unreviewed", request: request)],
            plan: .live, simulate: AdvisorSynthetic.simulate(.init(baseline: 0)))
        #expect(report.decisions == 1)
        #expect(report.available == 1)
        #expect(report.reviewed == 0)
        #expect(report.accepted == 0)
        #expect(report.rows.first?.evaluations ?? 0 > 0)
    }
    @Test("A seasonal multiplier can change direction without changing the minion board")
    func seasonalDirection() async throws {
        var request = try RecruitPlannerTests.request(board: [
            AdvisorSynthetic.boardMinion(1, "economy", attack: 2, health: 2),
            AdvisorSynthetic.boardMinion(2, "end", attack: 2, health: 2)],
            texts: ["economy": "After you play a minion, get a Gold Coin.", "end": "At the end of your turn, get a Tavern Coin."])
        request.strategyCatalog = [AdvisorBuild(id: "a", name: "Economy", share: 1, core: ["economy"], addons: []),
                                   AdvisorBuild(id: "b", name: "End of turn", share: 1, core: ["end"], addons: [])]
        let before = try await AdvisorEvaluation.run(request, plan: .live, simulate: AdvisorSynthetic.simulate(.init(baseline: 0)))
        #expect(before.advice.strategy?.buildID == "a")
        var trinket = Card(id: "repeat", dbfId: 99, name: "Repeater")
        trinket.text = "Your end of turn effects trigger an extra time."
        request.recruit?.definitions[trinket.id] = trinket
        request.recruit?.input.playerBoard.player.trinkets = [try JSONDecoder().decode(BattleTrinket.self,
            from: Data(#"{"cardId":"repeat","entityId":900,"scriptDataNum1":0,"scriptDataNum2":0,"scriptDataNum6":0}"#.utf8))]
        let after = try await AdvisorEvaluation.run(request, plan: .live, simulate: AdvisorSynthetic.simulate(.init(baseline: 0)))
        #expect(after.advice.strategy?.buildID == "b")
    }
    @Test("Acquisition guidance excludes higher-tier targets and reserves purchase gold")
    func acquisitionBudget() async throws {
        var request = try RecruitPlannerTests.request(board: [AdvisorSynthetic.boardMinion(1, "engine", attack: 3, health: 3)], gold: 5)
        request.tier = 3; request.rollCost = 1
        request.poolTiers = ["engine": 3, "payoff": 6, "filler": 2]
        request.strategyCatalog = [AdvisorBuild(id: "growth", name: "Growth", share: 1,
            core: ["engine", "payoff"], addons: [], coreTiers: ["engine": 3, "payoff": 6])]
        let result = try await AdvisorEvaluation.run(request, plan: .live, simulate: AdvisorSynthetic.simulate(.init(baseline: 0)))
        #expect(result.advice.strategy?.search?.eligibleTargets.isEmpty == true)
        #expect(result.advice.strategy?.search?.affordableRefreshes == 2)
        #expect(result.advice.strategy?.search?.minimumPurchaseGold == 3)
    }
}
