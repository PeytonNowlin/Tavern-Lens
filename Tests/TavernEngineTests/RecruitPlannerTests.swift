import Foundation
import Testing
import TavernEngine

@Suite("Recruit planner decision quality")
struct RecruitPlannerTests {
    typealias S = AdvisorSynthetic

    static func request(board: [AdvisorCard] = [], hand: [AdvisorCard] = [], shop: [AdvisorCard] = [],
                        gold: Int = 3, texts: [String: String] = [:]) throws -> AdvisorRequest {
        var r = try S.request(shop: shop, hand: hand, gold: gold, levelCost: nil, rollCost: nil,
                              canFreeze: false, board: board)
        var input = r.preview.input!
        input.playerBoard.player.heroPowers = []; input.playerBoard.player.secrets = []
        input.playerBoard.player.trinkets = []; input.playerBoard.player.questEntities = []
        input.playerBoard.player.globalInfo = [:]; input.playerBoard.player.hpLeft = 30
        var definitions: [String: Card] = [:]
        for (i, c) in (board + hand + shop).enumerated() {
            var d = Card(id: c.cardID, dbfId: i + 1, name: c.cardID)
            d.type = c.isMinion ? "MINION" : "SPELL"; d.text = texts[c.cardID]
            d.attack = c.entity.attack; d.health = c.entity.health; d.cost = c.cost
            if d.text?.contains("Battlecry") == true { d.mechanics = ["BATTLECRY"] }
            definitions[c.cardID] = d
        }
        var coin = Card(id: "BG28_810", dbfId: 999, name: "Tavern Coin")
        coin.type = "SPELL"; coin.cost = 0; coin.text = "Gain 1 Gold."
        definitions[coin.id] = coin
        r.recruit = RecruitContext(input: input, definitions: definitions)
        return r
    }

    static func action(_ kind: RecruitStep.Kind, _ state: RecruitState, _ context: RecruitContext,
                       id: Int? = nil) throws -> RecruitStep {
        try #require(RecruitPlanner.actions(state, context: context).first { $0.kind == kind && (id == nil || $0.entityID == id) })
    }

    @Test("Buy/play resolves the battlecry and a generated coin can fund the next purchase")
    func battlecryAndGold() throws {
        let card = S.shopMinion(1, attack: 3, health: 1, cardID: "collector")
        let r = try Self.request(shop: [card], texts: ["collector": "Battlecry: Get a Tavern Coin."])
        let c = r.recruit!
        var s = RecruitState(request: r, context: c)
        s = try #require(RecruitPlanner.applying(Self.action(.buy, s, c), to: s, context: c))
        #expect(s.gold == 0 && s.hand.count == 1 && s.board.isEmpty)
        s = try #require(RecruitPlanner.applying(Self.action(.play, s, c), to: s, context: c))
        #expect(s.board.count == 1 && s.hand.first?.cardID == "BG28_810")
        s = try #require(RecruitPlanner.applying(Self.action(.spell, s, c), to: s, context: c))
        #expect(s.gold == 1 && s.hand.isEmpty)
        #expect(r.shop.count == 1, "search cannot mutate observed state")
    }

    @Test("Targeted battlecry applies to the chosen minion, not merely the purchased body's stats")
    func targetBattlecry() throws {
        let board = [S.boardMinion(1, "body", attack: 2, health: 3)]
        let hand = [S.shopMinion(2, attack: 1, health: 1, cardID: "buffer")]
        let r = try Self.request(board: board, hand: hand, texts: ["buffer": "Battlecry: Give a minion +4/+5."])
        let c = r.recruit!, s = RecruitState(request: r, context: r.recruit!)
        let next = try #require(RecruitPlanner.applying(Self.action(.play, s, c), to: s, context: c))
        #expect(next.board[0].entity.attack == 6 && next.board[0].entity.health == 8)
    }

    @Test("Unsupported random battlecry is not treated as a vanilla purchase")
    func unsupported() throws {
        let r = try Self.request(shop: [S.shopMinion(1, attack: 20, health: 20, cardID: "random")],
                                 texts: ["random": "Battlecry: Gain a random Bonus Keyword."])
        let result = RecruitPlanner.search(r, context: r.recruit!)
        #expect(result.plans.isEmpty)
        #expect(result.limitations.contains { $0.contains("Unmodelled play") })
    }

    @Test("A buy then play can be recommended before any opponent has been seen")
    func unseen() async throws {
        var r = try Self.request(shop: [S.shopMinion(1, attack: 4, health: 4, cardID: "body")])
        r.preview.input = nil; r.preview.opponentSeenTurn = nil
        let result = try await AdvisorEvaluation.run(r, plan: .live, simulate: S.simulate(.init(baseline: 0)))
        let suggestion = try #require(result.advice.suggestions.first)
        #expect(suggestion.continuation == ["Buy body", "Play body"])
        #expect(suggestion.odds == nil)
        #expect(abs(suggestion.terms.total - suggestion.gain) < 0.00001)
        #expect(result.evaluations == 0)
    }

    @Test("Every sell is explored; a small scaling multiplier is worth preserving")
    func protectEngine() throws {
        let board = [S.boardMinion(1, "surveyor", attack: 1, health: 1),
                     S.boardMinion(2, "generator", attack: 2, health: 2)]
        let r = try Self.request(board: board, texts: ["surveyor": "Blood Gems played from your hand cast an extra time.",
                                                      "generator": "Rally: Get 2 Blood Gems."])
        let c = r.recruit!, s = RecruitState(request: r, context: r.recruit!)
        #expect(RecruitPlanner.actions(s, context: c).filter { $0.kind == .sell }.count == 2)
        let after = try #require(RecruitPlanner.applying(Self.action(.sell, s, c, id: 1), to: s, context: c))
        #expect(RecruitPlanner.value(after, request: r, context: c).total < RecruitPlanner.value(s, request: r, context: c).total)
        #expect(RecruitPlanner.search(r, context: c).plans.allSatisfy { $0.state.steps.last?.kind != .sell || $0.value.total < RecruitPlanner.value(s, request: r, context: c).total })
    }

    @Test("Full board plans sell filler, buy and play without exceeding available gold")
    func fullBoardSequence() throws {
        let board = (1...7).map { S.boardMinion($0, "body\($0)", attack: $0, health: $0) }
        let r = try Self.request(board: board, shop: [S.shopMinion(20, attack: 30, health: 30, cardID: "upgrade")], gold: 2)
        let search = RecruitPlanner.search(r, context: r.recruit!)
        let plan = try #require(search.plans.first { $0.state.board.contains { $0.cardID == "upgrade" } })
        #expect(plan.state.steps.map(\.kind).contains(.sell))
        #expect(plan.state.gold >= 0 && plan.state.board.count == 7)
        #expect(plan.state.board.contains { $0.entity.entityId == 7 })
    }

    @Test("Triple consumes three copies, combines buffs and creates the golden in hand")
    func triple() throws {
        let board = [S.boardMinion(1, "pair", attack: 3, health: 4), S.boardMinion(2, "pair", attack: 2, health: 3)]
        var r = try Self.request(board: board, shop: [S.shopMinion(3, attack: 2, health: 3, cardID: "pair")])
        var normal = r.recruit!.definitions["pair"]!; normal.attack = 2; normal.health = 3; normal.dbfId = 10; normal.battlegroundsPremiumDbfId = 11
        var golden = Card(id: "pair_G", dbfId: 11, name: "Golden pair")
        golden.type = "MINION"; golden.attack = 4; golden.health = 6; golden.battlegroundsNormalDbfId = 10
        r.recruit!.definitions["pair"] = normal; r.recruit!.definitions["pair_G"] = golden
        let c = r.recruit!, s = RecruitState(request: r, context: r.recruit!)
        var after = try #require(RecruitPlanner.applying(Self.action(.buy, s, c), to: s, context: c))
        #expect(after.board.isEmpty && after.hand.count == 1 && after.pendingDiscover == 1)
        #expect(after.hand[0].entity.attack == 5 && after.hand[0].entity.health == 7)
        after = try #require(RecruitPlanner.applying(Self.action(.play, after, c), to: after, context: c))
        #expect(after.terminal && !after.limitations.isEmpty)
    }

    @Test("Roll never invents cards or continues into the unknown shop")
    func rollBoundary() throws {
        var r = try Self.request(); r.rollCost = 1
        let c = r.recruit!, s = RecruitState(request: r, context: r.recruit!)
        let after = try #require(RecruitPlanner.applying(Self.action(.roll, s, c), to: s, context: c))
        #expect(after.terminal && after.gold == 2 && after.shop.isEmpty)
        #expect(RecruitPlanner.actions(after, context: c).isEmpty)
    }

    @Test("Old opponent boards are excluded and recent boards have explicit stress scenarios")
    func uncertainty() throws {
        var r = try Self.request(); r.preview.opponentSeenTurn = 3
        r.lobby = [try S.lobbyOpponent(2, seenTurn: 9), try S.lobbyOpponent(3, seenTurn: 4)]
        let scenarios = RecruitEvaluation.scenarios(r)
        #expect(scenarios.count == 2)
        #expect(scenarios.map(\.stress) == [false, true])
        #expect(scenarios[1].side.board[0].attack > scenarios[0].side.board[0].attack)
    }

    @Test("An incomplete simulation budget reproduces the same advice")
    func deterministicStops() async throws {
        let r = try Self.request(shop: [S.shopMinion(1, attack: 5, health: 5, cardID: "body")])
        let simulate = S.simulate(S.Stub(baseline: 0))
        let a = try await AdvisorEvaluation.run(r, plan: .live, limit: 3, simulate: simulate)
        let b = try await AdvisorEvaluation.run(r, plan: .live, limit: 3, simulate: simulate)
        #expect(a.advice == b.advice && a.evaluations == b.evaluations)
        #expect(a.advice.suggestions.allSatisfy { $0.confidence != .high })
    }

    @Test("At one health, unchecked levelling cannot be the recommendation")
    func survival() async throws {
        var r = try Self.request(board: [S.boardMinion(1, "body", attack: 2, health: 2)], gold: 10)
        r.levelCost = 1; r.recruit!.input.playerBoard.player.hpLeft = 1
        r.preview.opponentSeenTurn = 1
        let result = try await AdvisorEvaluation.run(r, plan: .live, simulate: S.simulate(.init(baseline: 0)))
        #expect(result.advice.suggestions.allSatisfy { if case .level = $0.action { return false }; return true })
    }

    @Test("Unsupported effects in already-played battlecries do not block future turns")
    func oldBattlecry() throws {
        let r = try Self.request(board: [S.boardMinion(1, "random", attack: 2, health: 3)],
                                 texts: ["random": "Battlecry: Gain a random Bonus Keyword."])
        let search = RecruitPlanner.search(r, context: r.recruit!)
        #expect(!search.limitations.contains { $0.contains("Unmodelled play") })
    }
    @Test("A held tavern spell does not pay its shop price a second time")
    func heldSpellIsFree() throws {
        let r = try Self.request(board: [S.boardMinion(1, "body", attack: 2, health: 2)],
                                 hand: [S.spell(2, "buff", cost: 3)], gold: 0,
                                 texts: ["buff": "Give a minion +4/+4."])
        let c = r.recruit!, state = RecruitState(request: r, context: r.recruit!)
        let after = try #require(RecruitPlanner.applying(Self.action(.spell, state, c), to: state, context: c))
        #expect(after.gold == 0 && after.board[0].entity.attack == 6)
    }

    @Test("A supported play trigger resolves and a battlecry multiplier doubles the actual effect")
    func triggers() throws {
        let r = try Self.request(board: [S.boardMinion(1, "engine", attack: 2, health: 2),
                                        S.boardMinion(2, "brann", attack: 2, health: 4)],
                                 hand: [S.shopMinion(3, attack: 1, health: 1, cardID: "collector")],
                                 texts: ["engine": "After you play a minion, gain +2/+3.",
                                         "brann": "Your Battlecries trigger twice.",
                                         "collector": "Battlecry: Get a Tavern Coin."])
        let c = r.recruit!, state = RecruitState(request: r, context: r.recruit!)
        let after = try #require(RecruitPlanner.applying(Self.action(.play, state, c), to: state, context: c))
        #expect(after.board[0].entity.attack == 4 && after.board[0].entity.health == 5)
        #expect(after.hand.filter { $0.cardID == "BG28_810" }.count == 2)
    }

    @Test("A supported hero power spends gold and cannot be used twice")
    func heroPower() throws {
        var r = try Self.request(board: [S.boardMinion(1, "body", attack: 2, health: 2)])
        var p = try CombatGoldens.input(CombatGoldens.fullGameTurn11).playerBoard.player.heroPowers[0]
        p.cardId = "power"; p.used = false; p.locked = 0
        r.recruit!.input.playerBoard.player.heroPowers = [p]
        r.recruit!.powerCosts["power"] = 1
        var d = Card(id: "power", dbfId: 100, name: "Buff power"); d.text = "Give a minion +2/+2."
        r.recruit!.definitions["power"] = d
        let c = r.recruit!, state = RecruitState(request: r, context: r.recruit!)
        let after = try #require(RecruitPlanner.applying(Self.action(.power, state, c), to: state, context: c))
        #expect(after.gold == 2 && after.board[0].entity.attack == 4)
        #expect(!RecruitPlanner.actions(after, context: c).contains { $0.kind == .power })
    }

    @Test("A full hand cannot buy and an unaffordable action is rejected")
    func legality() throws {
        let card = S.shopMinion(99, attack: 8, health: 8, cardID: "expensive")
        var r = try Self.request(hand: (1...10).map { S.shopMinion($0, attack: 1, health: 1, cardID: "h\($0)") }, shop: [card])
        let c = r.recruit!, state = RecruitState(request: r, context: r.recruit!)
        #expect(!RecruitPlanner.actions(state, context: c).contains { $0.kind == .buy })
        r.hand = []; r.gold = 0
        let step = RecruitStep(kind: .buy, entityID: 99, action: .buy(shop: 0, cardID: "expensive", place: 0), title: "Buy")
        #expect(RecruitPlanner.applying(step, to: RecruitState(request: r, context: c), context: c) == nil)
    }

    @Test("Supported end-of-turn buffs reach the combat board exactly once")
    func endOfTurn() throws {
        let r = try Self.request(board: [S.boardMinion(1, "buffer", attack: 2, health: 2),
                                        S.boardMinion(2, "body", attack: 2, health: 2)],
                                 texts: ["buffer": "At the end of your turn, give your other minions +2/+3."])
        let result = RecruitPlanner.search(r, context: r.recruit!).baseline.projection
        #expect(result.board[0].entity.attack == 2)
        #expect(result.board[1].entity.attack == 4 && result.board[1].entity.health == 5)
        #expect(result.limitations.isEmpty)
    }

    @Test("A held Sludge Corrosion buffs the board; its discard clause is not applied on cast")
    func sludgeCast() throws {
        let r = try Self.request(board: [S.boardMinion(1, "body", attack: 2, health: 2)],
                                 hand: [S.spell(2, "sludge", cost: 1)], gold: 0,
                                 texts: ["sludge": "Give your minions +1/+1. If you discard this, cast it twice."])
        let c = r.recruit!, state = RecruitState(request: r, context: r.recruit!)
        let after = try #require(RecruitPlanner.applying(Self.action(.spell, state, c), to: state, context: c))
        #expect(after.board[0].entity.attack == 3 && after.board[0].entity.health == 3)
    }

    @Test("A stat-setting spell can be worse than keeping a large minion")
    func statSetting() throws {
        let r = try Self.request(board: [S.boardMinion(1, "large", attack: 60, health: 60)],
                                 hand: [S.spell(2, "set", cost: 2)],
                                 texts: ["set": "Set a minion's stats to 20/20."])
        let c = r.recruit!, state = RecruitState(request: r, context: r.recruit!)
        let after = try #require(RecruitPlanner.applying(Self.action(.spell, state, c), to: state, context: c))
        #expect(after.board[0].entity.attack == 20 && after.board[0].entity.health == 20)
        #expect(RecruitPlanner.value(after, request: r, context: c).total < RecruitPlanner.value(state, request: r, context: c).total)
    }

    @Test("Deity buffs update the simulator tags and have strategic value without opponent history")
    func deityBuff() throws {
        var r = try Self.request(board: [S.boardMinion(1, "body", attack: 2, health: 2)],
                                 hand: [S.spell(2, "deitySpell", cost: 1)], gold: 0,
                                 texts: ["deitySpell": "Give your Deity +7/+7."])
        let json = #"{"entityId":20,"cardId":"BG_OldGod","scriptDataNum1":0,"scriptDataNum2":4,"scriptDataNum3":5,"scriptDataNum6":0,"tags":{"4914":4,"4915":5}}"#
        r.recruit!.input.playerBoard.player.secrets = [try JSONDecoder().decode(BattleSecret.self, from: Data(json.utf8))]
        let c = r.recruit!, state = RecruitState(request: r, context: r.recruit!)
        let after = try #require(RecruitPlanner.applying(Self.action(.spell, state, c), to: state, context: c))
        #expect(after.input.playerBoard.player.secrets[0].tags?["4914"] == 11)
        #expect(after.input.playerBoard.player.secrets[0].tags?["4915"] == 12)
        #expect(RecruitPlanner.value(after, request: r, context: c).total > RecruitPlanner.value(state, request: r, context: c).total)
    }

    @Test("A one-time battlecry reward is not mistaken for a recurring economy engine")
    func cycleBodyIsNotEngine() throws {
        let body = S.boardMinion(1, "collector", attack: 3, health: 1)
        let r = try Self.request(board: [body], texts: ["collector": "Battlecry: Get a Tavern Coin."])
        let c = r.recruit!, state = RecruitState(request: r, context: r.recruit!)
        #expect(RecruitPlanner.production(body, state: state, context: c) == 0)
    }

    @Test("An end-of-turn multiplier repeats the buff before combat")
    func endOfTurnMultiplier() throws {
        let r = try Self.request(board: [S.boardMinion(1, "buffer", attack: 2, health: 2),
                                        S.boardMinion(2, "multiplier", attack: 2, health: 2)],
                                 texts: ["buffer": "At the end of your turn, give your other minions +2/+3.",
                                         "multiplier": "Your end of turn effects trigger twice."])
        let result = RecruitPlanner.search(r, context: r.recruit!).baseline.projection
        #expect(result.board[1].entity.attack == 6 && result.board[1].entity.health == 8)
    }

    @Test("A passive trinket does not disable combat projection")
    func passiveTrinket() throws {
        var r = try Self.request(board: [S.boardMinion(1, "body", attack: 2, health: 2)])
        let json = #"{"cardId":"BG30_MagicItem_888","entityId":347,"scriptDataNum1":3,"scriptDataNum2":0,"scriptDataNum6":1}"#
        r.recruit!.input.playerBoard.player.trinkets = [try JSONDecoder().decode(BattleTrinket.self, from: Data(json.utf8))]
        var d = Card(id: "BG30_MagicItem_888", dbfId: 100, name: "Souvenir Stand")
        d.text = "When you buy a Greater Trinket, this transforms into a copy of it."
        r.recruit!.definitions[d.id] = d
        #expect(RecruitPlanner.search(r, context: r.recruit!).baseline.projection.limitations.isEmpty)
    }

    @Test("Sharpened Sword on a minion triggers when a card is played")
    func darkGiftPlay() throws {
        var body = S.boardMinion(1, "body", attack: 2, health: 2)
        let json = #"{"cardId":"BG36_MidGameEffect_000t74e","originEntityId":90,"timing":0}"#
        body.entity.enchantments = [try JSONDecoder().decode(BattleEnchantment.self, from: Data(json.utf8))]
        var r = try Self.request(board: [body], hand: [S.spell(2, "BG28_810", cost: 0)])
        var d = Card(id: "BG36_MidGameEffect_000t74e", dbfId: 100, name: "Sharpened Sword")
        d.text = "Whenever you play a card, gain +3 Attack."
        r.recruit!.definitions[d.id] = d
        let c = r.recruit!, state = RecruitState(request: r, context: c)
        let after = try #require(RecruitPlanner.applying(Self.action(.spell, state, c), to: state, context: c))
        #expect(after.board[0].entity.attack == 5)
    }

    @Test("A Deity deathrattle contributes production beyond the minion body")
    func aberrationProduction() throws {
        let body = S.boardMinion(1, "sacrifice", attack: 2, health: 2)
        var r = try Self.request(board: [body], texts: ["sacrifice": "Reborn Deathrattle: Give your Deity +2/+1."])
        let json = #"{"entityId":20,"cardId":"BG_OldGod","scriptDataNum1":2,"scriptDataNum2":4,"scriptDataNum3":5,"scriptDataNum6":0,"tags":{"4914":4,"4915":5}}"#
        r.recruit!.input.playerBoard.player.secrets = [try JSONDecoder().decode(BattleSecret.self, from: Data(json.utf8))]
        let c = r.recruit!, state = RecruitState(request: r, context: c)
        #expect(RecruitPlanner.production(body, state: state, context: c) > 0)
    }

    @Test("Discarding Sludge uses both Portraits without playing it or inventing the random reward")
    func doublePortraitDiscard() throws {
        let envoy = S.boardMinion(1, "envoy", attack: 2, health: 2)
        var r = try Self.request(board: [envoy], hand: [S.spell(2, "BG36_301t", cost: 1)], gold: 0,
            texts: ["envoy": "Activate (0): Discard a card to get a random Tavern spell.",
                    "BG36_301t": "Give your minions +1/+1. If you discard this, cast it twice."])
        let json = #"{"cardId":"portrait","entityId":347,"scriptDataNum1":1,"scriptDataNum2":1,"scriptDataNum6":1}"#
        let portrait = try JSONDecoder().decode(BattleTrinket.self, from: Data(json.utf8))
        r.recruit!.input.playerBoard.player.trinkets = [portrait, portrait]
        var d = Card(id: "portrait", dbfId: 100, name: "Sludge Portrait")
        d.text = "Get a Sludge Corrosion. After you discard a card, get a Sludge Corrosion."
        r.recruit!.definitions[d.id] = d
        r.recruit!.activations = [1: .init(ready: true, cost: 0)]
        let c = r.recruit!, state = RecruitState(request: r, context: c)
        let step = try Self.action(.activate, state, c)
        let after = try #require(RecruitPlanner.applying(step, to: state, context: c))
        #expect(after.board[0].entity.attack == 4 && after.board[0].entity.health == 4)
        #expect(after.hand.count == 2 && after.hand.allSatisfy { $0.cardID == "BG36_301t" })
        #expect(after.unknownRewards == 1 && after.terminal)
        #expect(after.combatInput.playerBoard.player.globalInfo["CardsDiscardedThisGame"] == 1)
        #expect(after.combatInput.playerBoard.player.globalInfo["TavernSpellsCastThisGame"] == 2)
        #expect(after.usedActivations.contains(1))
        #expect(RecruitPlanner.applying(step, to: after, context: c) == nil)
        #expect(RecruitPlanner.value(after, request: r, context: c).total > RecruitPlanner.value(state, request: r, context: c).total)
        var unavailable = c; unavailable.activations = [1: .init(ready: false, cost: 0)]
        #expect(!RecruitPlanner.actions(state, context: unavailable).contains { $0.kind == .activate })
        unavailable.activations = nil
        #expect(!RecruitPlanner.actions(state, context: unavailable).contains { $0.kind == .activate })
    }

    @Test("Combat Dark Gifts change valuation without applying their stats before combat")
    func darkGiftCombatValue() throws {
        var body = S.boardMinion(1, "body", attack: 20, health: 20)
        var r = try Self.request(board: [body])
        let c = r.recruit!, plain = RecruitState(request: r, context: c)
        let json = #"{"cardId":"BG36_MidGameEffect_000t81e","originEntityId":90,"timing":0}"#
        body.entity.enchantments = [try JSONDecoder().decode(BattleEnchantment.self, from: Data(json.utf8))]
        var d = Card(id: "BG36_MidGameEffect_000t81e", dbfId: 100, name: "Transcendence")
        d.text = "Start of Combat: Triple this minion's stats."
        r.recruit!.definitions[d.id] = d; r.board = [body]
        let state = RecruitState(request: r, context: r.recruit!)
        #expect(RecruitPlanner.value(state, request: r, context: r.recruit!).tempo > RecruitPlanner.value(plain, request: r, context: c).tempo)
        let projected = RecruitEffects.combatProjection(state, context: r.recruit!)
        #expect(projected.board[0].entity.attack == 20)
        #expect(projected.combatInput.playerBoard.board[0].enchantments.count == 1)
    }

    @Test("Flaming Enforcer projects the observed highest-health Tavern minion")
    func consumeProjection() throws {
        let r = try Self.request(board: [S.boardMinion(1, "enforcer", attack: 71, health: 71)],
            shop: [S.shopMinion(2, attack: 67, health: 68, cardID: "food"), S.shopMinion(3, attack: 80, health: 5, cardID: "other")],
            texts: ["enforcer": "At the end of your turn, consume the highest-Health minion in the Tavern to gain its stats."])
        let c = r.recruit!, state = RecruitState(request: r, context: c)
        let after = RecruitEffects.combatProjection(state, context: c)
        #expect(after.board[0].entity.attack == 138 && after.board[0].entity.health == 139)
        #expect(after.limitations.isEmpty)
    }

    @Test("Discard Portrait rewards fill the hand before the random activator reward")
    func discardHandLimit() throws {
        var r = try Self.request(board: [S.boardMinion(1, "envoy", attack: 2, health: 2)],
            hand: (2...11).map { S.spell($0, "BG36_301t", cost: 1) }, gold: 0,
            texts: ["envoy": "Activate (0): Discard a card to get a random Tavern spell.",
                    "BG36_301t": "Give your minions +1/+1. If you discard this, cast it twice."])
        let json = #"{"cardId":"portrait","entityId":347,"scriptDataNum1":1,"scriptDataNum2":1,"scriptDataNum6":1}"#
        let portrait = try JSONDecoder().decode(BattleTrinket.self, from: Data(json.utf8))
        r.recruit!.input.playerBoard.player.trinkets = [portrait, portrait]
        var d = Card(id: "portrait", dbfId: 100, name: "Sludge Portrait")
        d.text = "Get a Sludge Corrosion. After you discard a card, get a Sludge Corrosion."
        r.recruit!.definitions[d.id] = d
        r.recruit!.activations = [1: .init(ready: true, cost: 0)]
        let c = r.recruit!, state = RecruitState(request: r, context: c)
        let after = try #require(RecruitPlanner.applying(Self.action(.activate, state, c), to: state, context: c))
        #expect(after.hand.count == 10 && after.unknownRewards == 0)
        #expect(after.board[0].entity.attack == 4)
    }

    @Test("The advisor does not sell three bodies for a Venomous minion without a survival benefit")
    func noDestructiveSporePlan() async throws {
        var spore = S.shopMinion(20, attack: 1, health: 1, cardID: "spore")
        spore.entity.venomous = true
        var r = try Self.request(board: (1...4).map { S.boardMinion($0, "body\($0)", attack: 2, health: 2) },
                                 shop: [spore], gold: 0)
        r.preview.input = nil
        let result = try await AdvisorEvaluation.run(r, plan: .live, simulate: S.simulate(.init(baseline: 0)))
        #expect(result.advice.suggestions.allSatisfy {
            ($0.continuation ?? []).filter { $0.hasPrefix("Sell ") }.count <= 1
        })
    }

    @Test("Spell Siphon adds only the new cast counter, alongside Sharpened Sword's play trigger")
    func giftCounters() throws {
        var body = S.boardMinion(1, "body", attack: 20, health: 20)
        let json = #"[{"cardId":"BG36_MidGameEffect_000t30e","originEntityId":90,"timing":0},{"cardId":"BG36_MidGameEffect_000t74e","originEntityId":91,"timing":0}]"#
        body.entity.enchantments = try JSONDecoder().decode([BattleEnchantment].self, from: Data(json.utf8))
        var r = try Self.request(board: [body], hand: [S.spell(2, "buff", cost: 1)], texts: ["buff": "Give your minions +1/+1."])
        for (id, text) in ["BG36_MidGameEffect_000t30e": "Has +3/+3 for each Tavern spell you've cast this game. (0)",
                           "BG36_MidGameEffect_000t74e": "Whenever you play a card, gain +3 Attack."] {
            var d = Card(id: id, dbfId: 100, name: id); d.text = text; r.recruit!.definitions[id] = d
        }
        let c = r.recruit!, state = RecruitState(request: r, context: c)
        let after = try #require(RecruitPlanner.applying(Self.action(.spell, state, c), to: state, context: c))
        #expect(after.board[0].entity.attack == 27 && after.board[0].entity.health == 24)
    }

}
