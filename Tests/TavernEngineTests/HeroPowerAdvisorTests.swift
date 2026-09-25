import Foundation
import Testing
import TavernEngine

@Suite("Hero power recruit advice")
struct HeroPowerAdvisorTests {
    static func request(_ id: String = "BG21_HERO_010p") throws -> AdvisorRequest {
        var r = try RecruitPlannerTests.request(gold: 2)
        var p = try CombatGoldens.input(CombatGoldens.fullGameTurn11).playerBoard.player.heroPowers[0]
        p.cardId = id; p.used = false; p.locked = 0
        r.recruit!.input.playerBoard.player.heroPowers = [p]
        r.recruit!.powerCosts[id] = 2
        var card = Card(id: id, dbfId: 76563, name: id == "BG21_HERO_010p" ? "I Spy" : "Dark Ritual")
        card.type = "HERO_POWER"
        card.text = id == "BG21_HERO_010p"
            ? "[x]<b>Discover</b> a plain copy of\na minion from your next\nopponent's warband."
            : "[x]Get 2 random minions.\nWhen you play one,\ndiscard the other."
        r.recruit!.definitions[id] = card
        r.preview.input = nil
        return r
    }

    @Test("I Spy and Dark Ritual from recent matches are offered when affordable", arguments: ["BG21_HERO_010p", "BG36_HERO_002p"])
    func offered(_ id: String) throws {
        let r = try Self.request(id), c = r.recruit!
        #expect(RecruitPlanner.actions(RecruitState(request: r, context: c), context: c).contains { $0.kind == .power })
    }

    static func linkedRequest(pending: Bool = false) throws -> AdvisorRequest {
        var log = LobbySyntheticTests.lobbyGame()
        log.turn(5); log.gameTag("2022", "1"); log.localTag("RESOURCES", "2")
        log.heroPower(136, "BG36_HERO_002p", controller: SyntheticLog.localPlayerID, extra: ["COST=2", "EXHAUSTED=0"])
        var definitions = Array(try request("BG36_HERO_002p").recruit!.definitions.values)
        for i in 1...4 {
            log.card(300 + i, "body\(i)", controller: SyntheticLog.localPlayerID, zone: "HAND", position: i,
                     health: i, extra: ["ATK=\(i)"])
            log.playerEnchantment(400 + i, "BG36_308e", controller: SyntheticLog.localPlayerID,
                attachedTo: 300 + i, extra: ["TAG_SCRIPT_DATA_NUM_1=1", "TAG_SCRIPT_DATA_NUM_2=136",
                    "TAG_SCRIPT_DATA_NUM_3=\((i - 1) / 2)"])
            var card = Card(id: "body\(i)", dbfId: i, name: "body\(i)")
            card.type = "MINION"; card.attack = i; card.health = i
            definitions.append(card)
        }
        if pending { log.choices(id: 33, type: "GENERAL", source: "136", options: [(500, "choice", "SETASIDE")]) }
        log.endTaskList()
        var engine = TavernEngine(cards: CardDB(build: 253216, cards: definitions))
        for line in log.lines { engine.ingest(line) }
        return try #require(engine.advisorRequest)
    }

    @Test("Playing a Dark Ritual minion discards only its linked partner")
    func linkedDiscard() throws {
        let r = try Self.linkedRequest(), c = try #require(r.recruit)
        let before = RecruitState(request: r, context: c)
        let play = try RecruitPlannerTests.action(.play, before, c, id: 301)
        let after = try #require(RecruitPlanner.applying(play, to: before, context: c))
        #expect(after.hand.map(\.entity.entityId) == [303, 304])
        #expect(after.board.map(\.entity.entityId) == [301])
        #expect(after.input.playerBoard.player.globalInfo["CardsDiscardedThisGame"] == 1)
    }

    @Test("Unknown rewards spend the observed cost without inventing cards", arguments: ["BG21_HERO_010p", "BG36_HERO_002p"])
    func transition(_ id: String) throws {
        let r = try Self.request(id), c = r.recruit!, before = RecruitState(request: r, context: r.recruit!)
        let step = try RecruitPlannerTests.action(.power, before, c)
        let after = try #require(RecruitPlanner.applying(step, to: before, context: c))
        #expect(after.gold == 0 && after.terminal)
        #expect(after.board == before.board && after.hand == before.hand)
        #expect(after.input.playerBoard.player.heroPowers[0].used)
        #expect(after.input.playerBoard.player.globalInfo["GoldSpentThisGame"] == 2)
        #expect(RecruitPlanner.actions(after, context: c).isEmpty)
        #expect(!after.limitations.isEmpty)
        #expect(!RecruitPlanner.search(r, context: c).limitations.contains { $0.contains("Unmodelled hero power") })
    }

    @Test("Both powers reach displayed advice with uncertainty", arguments: ["BG21_HERO_010p", "BG36_HERO_002p"])
    func advice(_ id: String) async throws {
        let r = try Self.request(id)
        let result = try await AdvisorEvaluation.run(r, plan: .live, simulate: AdvisorSynthetic.simulate(.init(baseline: 0)))
        let first = try #require(result.advice.suggestions.first)
        #expect(first.action.group == "heroPower")
        #expect(first.confidence == .low && first.odds == nil)
        #expect(first.reason.contains("reassess"))
    }

    @Test("Powers respect readiness, cost and reward hand capacity", arguments: ["BG21_HERO_010p", "BG36_HERO_002p"])
    func unavailable(_ id: String) throws {
        let base = try Self.request(id)
        for condition in 0...4 {
            var r = base
            switch condition {
            case 0: r.gold = 1
            case 1: r.recruit!.input.playerBoard.player.heroPowers[0].used = true
            case 2: r.recruit!.input.playerBoard.player.heroPowers[0].locked = 1
            case 3: r.recruit!.powerCosts[id] = nil
            default:
                r.hand = (1...(id == "BG36_HERO_002p" ? 9 : 10)).map {
                    AdvisorSynthetic.shopMinion($0, attack: 1, health: 1, cardID: "held\($0)")
                }
            }
            let c = r.recruit!
            #expect(!RecruitPlanner.actions(RecruitState(request: r, context: c), context: c).contains { $0.kind == .power })
        }
    }

    @Test("Known strong shop buys beat speculative hero rewards")
    func strongBuy() async throws {
        var r = try Self.request()
        let shop = try RecruitPlannerTests.request(shop: [AdvisorSynthetic.shopMinion(1, attack: 30, health: 30, cardID: "strong")])
        r.shop = shop.shop; r.gold = 3
        r.recruit!.definitions.merge(shop.recruit!.definitions) { a, _ in a }
        let result = try await AdvisorEvaluation.run(r, plan: .live, simulate: AdvisorSynthetic.simulate(.init(baseline: 0)))
        #expect(result.advice.suggestions.first?.action.group == "buy:s0")
    }

    @Test("An outstanding choice blocks further recruit actions")
    func pendingChoice() throws {
        let r = try Self.linkedRequest(pending: true), c = r.recruit!
        #expect(c.pendingChoice == true)
        #expect(RecruitPlanner.actions(RecruitState(request: r, context: c), context: c).isEmpty)
    }

    @Test("Changed power text remains an explicit coverage gap")
    func changedText() throws {
        var r = try Self.request()
        r.recruit!.definitions["BG21_HERO_010p"]!.text = "Discover a minion and destroy your warband."
        let result = RecruitPlanner.search(r, context: r.recruit!)
        #expect(!result.plans.contains { $0.state.steps.contains { $0.kind == .power } })
        #expect(result.limitations.contains { $0.contains("Unmodelled hero power") })
    }

    @Test("Archived match powers are offered when restoring their two-gold decision budget")
    func capturedMatches() throws {
        guard let directory = ProcessInfo.processInfo.environment["TAVERN_HERO_POWER_AUDIT_DIRECTORY"] else { return }
        for (file, id) in [("game-1110347169-turn-4.json", "BG21_HERO_010p"), ("game-687825623-turn-9.json", "BG36_HERO_002p")] {
            let data = try Data(contentsOf: URL(fileURLWithPath: directory).appendingPathComponent(file))
            var r = try #require(JSONDecoder().decode(AdvisorTurnDiagnostic.self, from: data).request)
            let c = try #require(r.recruit)
            #expect(c.input.playerBoard.player.heroPowers.contains { $0.cardId == id && !$0.used })
            // Turn-end snapshots have spent gold: this explicitly tests a restored budget,
            // not a claim about the advice originally displayed earlier in the turn.
            r.gold = 2
            #expect(RecruitPlanner.actions(RecruitState(request: r, context: c), context: c).contains { $0.kind == .power })
        }
    }

    @Test("Linked discard triggers Sludge Portrait and refuses missing batch data")
    func discardEffects() throws {
        var r = try Self.linkedRequest()
        let trinket = try JSONDecoder().decode(BattleTrinket.self, from: Data(#"{"cardId":"portrait","entityId":900,"scriptDataNum1":0,"scriptDataNum2":0,"scriptDataNum6":1}"#.utf8))
        r.recruit!.input.playerBoard.player.trinkets = [trinket]
        var portrait = Card(id: "portrait", dbfId: 900, name: "Sludge Portrait")
        portrait.text = "Get a Sludge Corrosion. After you discard a card, get a Sludge Corrosion."
        var sludge = Card(id: "BG36_301t", dbfId: 901, name: "Sludge Corrosion"); sludge.type = "SPELL"
        sludge.text = "Give your minions +1/+1. If you discard this, cast it twice."
        r.recruit!.definitions["portrait"] = portrait; r.recruit!.definitions[sludge.id] = sludge
        let c = r.recruit!, before = RecruitState(request: r, context: c)
        let step = try RecruitPlannerTests.action(.play, before, c, id: 301)
        let after = try #require(RecruitPlanner.applying(step, to: before, context: c))
        #expect(after.hand.contains { $0.cardID == "BG36_301t" })
        #expect(after.hand.count == 3)
        r.recruit!.linkedDiscards = nil
        #expect(RecruitPlanner.applying(step, to: before, context: r.recruit!) == nil)
        #expect(RecruitPlanner.search(r, context: r.recruit!).limitations.contains { $0.contains("Discard partner unknown") })
    }
}
