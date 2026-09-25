import Foundation
import Testing
import TavernEngine
import HSLog

@Suite("Dark Discovery advisor")
struct DarkDiscoveryTests {
    static let id = "BG36_Button_DarkGift"

    static func request(extra: [String] = [], gold: Int = 3, pending: Bool = false) throws -> AdvisorRequest {
        var log = LobbySyntheticTests.lobbyGame()
        log.turn(5)
        log.gameTag("2022", "1")
        log.localTag("RESOURCES", String(gold))
        log.card(349, id, controller: SyntheticLog.localPlayerID, zone: "PLAY", position: 0,
            type: "GAME_MODE_BUTTON", extra: ["COST=3", "TAG_SCRIPT_DATA_NUM_2=3",
                "TAG_SCRIPT_DATA_NUM_3=2", "TAG_SCRIPT_DATA_NUM_4=2", "LOCK_VISUAL=0", "EXHAUSTED=0"] + extra)
        if pending {
            log.choices(id: 33, type: "GENERAL", source: "349", options: [(500, "minion", "SETASIDE")])
        }
        log.endTaskList()
        var definition = Card(id: id, dbfId: 123, name: "Dark Discovery")
        definition.type = "GAME_MODE_BUTTON"; definition.cost = 3
        var engine = TavernEngine(cards: CardDB(build: 253216, cards: [definition]))
        for line in log.lines { engine.ingest(line) }
        return try #require(engine.advisorRequest)
    }

    @Test("The logged three-gold Dark Discovery button is considered by the planner")
    func offered() throws {
        let r = try Self.request(), c = try #require(r.recruit)
        let steps = RecruitPlanner.actions(RecruitState(request: r, context: c), context: c)
        #expect(steps.contains { $0.title.contains("Dark Discovery") })
    }
    @Test("Discovery spends the observed price and stops at the unknown choice")
    func transition() throws {
        let r = try Self.request(), c = try #require(r.recruit)
        let d = try #require(c.darkDiscovery)
        #expect(d.cost == 3 && d.remainingUses == 3 && d.minTier == 2 && d.maxTier == 2)
        let state = RecruitState(request: r, context: c)
        let action = try #require(RecruitPlanner.actions(state, context: c).first { $0.kind == .darkDiscovery })
        let after = try #require(RecruitPlanner.applying(action, to: state, context: c))
        #expect(after.gold == state.gold - 3 && after.terminal)
        #expect(after.board == state.board && after.hand == state.hand)
        #expect(after.combatInput.playerBoard.player.globalInfo["GoldSpentThisGame"] == 3)
        #expect(RecruitPlanner.actions(after, context: c).isEmpty)
        #expect(RecruitPlanner.applying(action, to: after, context: c) == nil)
        #expect(after.limitations.contains { $0.contains("Dark Gift unknown") })
    }

    @Test("Locked, exhausted, depleted, unaffordable and full-hand discoveries are excluded")
    func unavailable() throws {
        for tags in [["LOCK_VISUAL=1"], ["EXHAUSTED=1"], ["CANT_READY=1"], ["TAG_SCRIPT_DATA_NUM_2=0"]] {
            let r = try Self.request(extra: tags), c = try #require(r.recruit)
            #expect(!RecruitPlanner.actions(RecruitState(request: r, context: c), context: c).contains { $0.kind == .darkDiscovery })
        }
        var r = try Self.request(gold: 2), c = try #require(r.recruit)
        #expect(!RecruitPlanner.actions(RecruitState(request: r, context: c), context: c).contains { $0.kind == .darkDiscovery })
        r = try Self.request()
        r.hand = (1...10).map { AdvisorSynthetic.spell($0, "coin", cost: 0) }
        c = try #require(r.recruit)
        #expect(!RecruitPlanner.actions(RecruitState(request: r, context: c), context: c).contains { $0.kind == .darkDiscovery })
        r.hand = []; c.darkDiscovery = nil
        #expect(!RecruitPlanner.actions(RecruitState(request: r, context: c), context: c).contains { $0.kind == .darkDiscovery })
    }

    @Test("Discovery reaches the visible advice without inventing a combat result")
    func advice() async throws {
        let r = try Self.request()
        let result = try await AdvisorEvaluation.run(r, plan: .live, simulate: AdvisorSynthetic.simulate(.init(baseline: 0)))
        let suggestion = try #require(result.advice.suggestions.first)
        guard case .darkDiscovery(let cost, _, _) = suggestion.action else {
            Issue.record("Dark Discovery missing from advice"); return
        }
        #expect(cost == 3 && suggestion.confidence == .low && suggestion.odds == nil)
        #expect(suggestion.reason.contains("3 uses left"))
    }

    @Test("Discovery is an alternative, not an automatic pick over a known strong purchase")
    func compareShop() async throws {
        let observed = try Self.request()
        var r = try RecruitPlannerTests.request(shop: [AdvisorSynthetic.shopMinion(900, attack: 30, health: 30, cardID: "strong")])
        r.recruit!.darkDiscovery = observed.recruit!.darkDiscovery
        let result = try await AdvisorEvaluation.run(r, plan: .live, simulate: AdvisorSynthetic.simulate(.init(baseline: 0)))
        let first = try #require(result.advice.suggestions.first)
        guard case .buy = first.action else { Issue.record("Known upgrade should beat speculative discovery"); return }
    }

    @Test("An open discover prevents suggesting another button press")
    func pendingChoice() throws {
        let r = try Self.request(pending: true), c = try #require(r.recruit)
        #expect(c.darkDiscovery?.ready == false)
        #expect(!RecruitPlanner.actions(RecruitState(request: r, context: c), context: c).contains { $0.kind == .darkDiscovery })
    }

    @Test("Captured match exposes each remaining-use count and disables the spent button",
          .enabled(if: ProcessInfo.processInfo.environment["TAVERN_ADVISOR_AUDIT_LOG"] != nil))
    func capturedMatch() throws {
        let path = try #require(ProcessInfo.processInfo.environment["TAVERN_ADVISOR_AUDIT_LOG"])
        var definition = Card(id: Self.id, dbfId: 123, name: "Dark Discovery")
        definition.type = "GAME_MODE_BUTTON"
        var engine = TavernEngine(cards: CardDB(build: nil, cards: [definition]))
        var published = 0, uses: Set<Int> = [], ready = false
        struct Complete: Error {}
        do {
            try LogFileReader.forEachLine(in: URL(filePath: path)) { line in
                engine.ingest(line)
                guard engine.timeline.count != published else { return }
                published = engine.timeline.count
                guard let r = engine.advisorRequest, let c = r.recruit, let d = c.darkDiscovery else { return }
                uses.insert(d.remainingUses)
                #expect(d.cost == 3)
                if d.ready, r.gold >= d.cost, r.hand.count < 10 {
                    ready = true
                    #expect(RecruitPlanner.actions(RecruitState(request: r, context: c), context: c).contains { $0.kind == .darkDiscovery })
                }
                if d.remainingUses == 0 {
                    #expect(!d.ready)
                    throw Complete()
                }
            }
        } catch is Complete {}
        #expect(ready && uses == [0, 1, 2, 3])
    }

    @Test("Do not sell for speculative board room; a necessary funding sale is allowed")
    func saleBeforeDiscovery() throws {
        let observed = try Self.request()
        var r = try RecruitPlannerTests.request(board: (1...7).map {
            AdvisorSynthetic.boardMinion($0, "body\($0)", attack: 1, health: 1)
        })
        r.recruit!.darkDiscovery = observed.recruit!.darkDiscovery
        for gold in [3, 2] {
            r.gold = gold
            let c = r.recruit!, initial = RecruitState(request: r, context: c)
            let sell = try RecruitPlannerTests.action(.sell, initial, c)
            let sold = try #require(RecruitPlanner.applying(sell, to: initial, context: c))
            let discover = try RecruitPlannerTests.action(.darkDiscovery, sold, c)
            let after = RecruitPlanner.applying(discover, to: sold, context: c)
            #expect((after != nil) == (gold == 2))
        }
    }

}
