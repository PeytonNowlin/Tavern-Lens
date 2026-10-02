import Foundation
import Testing
import TavernEngine

@Suite("Policy 11 recruit effect coverage")
struct AdvisorPolicy11EffectsTests {
    typealias S = AdvisorSynthetic

    static func definition(_ id: String, text: String, type: String = "MINION",
                           races: [String]? = nil, request: inout AdvisorRequest) {
        var card = request.recruit!.definitions[id] ?? Card(id: id, dbfId: 9999, name: id)
        card.text = text; card.type = type; card.races = races
        request.recruit!.definitions[id] = card
    }

    static func clockRequest(version: Int = 11) throws -> AdvisorRequest {
        var request = try RecruitPlannerTests.request(
            board: [S.boardMinion(1, "body", attack: 2, health: 3)],
            shop: [S.shopMinion(2, attack: 8, health: 8, cardID: "upgrade")], gold: 3)
        request.recruit!.evaluationVersion = version
        let id = "BG32_MagicItem_271"
        request.recruit!.input.playerBoard.player.trinkets = [try JSONDecoder().decode(BattleTrinket.self,
            from: Data("{\"cardId\":\"\(id)\",\"entityId\":100,\"scriptDataNum1\":0,\"scriptDataNum2\":0,\"scriptDataNum6\":0}".utf8))]
        definition(id, text: "Gain 2 Gold. Buy your Greater Trinket next turn instead of Turn 9.",
                   type: "BATTLEGROUND_TRINKET", request: &request)
        return request
    }

    @Test("Completed Ornate Clock allows purchase combat checks without granting its gold again")
    func completedClock() throws {
        for version in [10, 11] {
            let request = try Self.clockRequest(version: version), context = request.recruit!
            let search = RecruitPlanner.search(request, context: context, budget: .init(depth: 2, width: 12, expansions: 80))
            let purchases = search.plans.filter { $0.state.steps.first?.kind == .buy }
            #expect(!purchases.isEmpty)
            #expect(purchases.allSatisfy { $0.projection.limitations.isEmpty } == (version == 11))
            #expect(purchases.allSatisfy { $0.state.gold == 0 })
            #expect(search.baseline.state.gold == 3 && request.gold == 3)
        }
        var changed = try Self.clockRequest()
        changed.recruit!.definitions["BG32_MagicItem_271"]!.text = "At the end of your turn, gain 2 Gold."
        let search = RecruitPlanner.search(changed, context: changed.recruit!)
        #expect(search.plans.allSatisfy { !$0.projection.limitations.isEmpty })
    }

    @Test("Fortify casts from hand with no gold, adding only three Health and Taunt")
    func fortify() throws {
        var request = try RecruitPlannerTests.request(
            board: [S.boardMinion(1, "body", attack: 2, health: 3)],
            hand: [S.spell(2, "BG28_503")], gold: 0)
        Self.definition("BG28_503", text: "Give a minion +3 Health and Taunt.",
                        type: "BATTLEGROUND_SPELL", request: &request)
        for version in [10, 11] {
            request.recruit!.evaluationVersion = version
            let context = request.recruit!, state = RecruitState(request: request, context: context)
            let spells = RecruitPlanner.actions(state, context: context).filter { $0.kind == .spell }
            #expect(spells.count == (version == 11 ? 1 : 0))
            if version == 11 {
                let step = try #require(spells.first)
                let after = try #require(RecruitPlanner.applying(step, to: state, context: context))
                #expect(after.board[0].entity.attack == 2 && after.board[0].entity.health == 6)
                #expect(after.board[0].entity.maxHealth == 6 && after.board[0].entity.taunt)
                #expect(after.hand.isEmpty && after.gold == 0)
                #expect(state.board[0].entity.health == 3 && !state.board[0].entity.taunt)
                var invalid = step; invalid.targetID = 999
                #expect(RecruitPlanner.applying(invalid, to: state, context: context) == nil)
            }
        }
        request.recruit!.definitions["BG28_503"]!.text = "Give a minion +4 Health and Taunt."
        let context = request.recruit!, state = RecruitState(request: request, context: context)
        #expect(RecruitPlanner.actions(state, context: context).allSatisfy { $0.kind != .spell })
    }

    static func prisonRequest(golden: Bool = false, cost: Int = 1) throws -> AdvisorRequest {
        let id = golden ? "BG36_180_G" : "BG36_180"
        var request = try RecruitPlannerTests.request(
            board: [S.boardMinion(1, id, attack: 4, health: 5, golden: golden)],
            shop: [S.shopMinion(3, attack: 90, health: 65, cardID: "bought"),
                   S.shopMinion(4, attack: 8, health: 9, cardID: "later")], gold: 8)
        Self.definition(id, text: golden
            ? "Activate (1): Gain double the stats of the next minion you buy this turn."
            : "Activate (1): Gain the stats of the next minion you buy this turn.", races: ["ELEMENTAL"], request: &request)
        request.recruit!.evaluationVersion = 11
        request.recruit!.activations = [1: .init(ready: true, cost: cost)]
        return request
    }

    @Test("Living Prison uses its observed price and copies exactly the next purchased minion",
          arguments: [false, true])
    func prisonNextBuy(golden: Bool) throws {
        let request = try Self.prisonRequest(golden: golden, cost: 2), context = request.recruit!
        let initial = RecruitState(request: request, context: context)
        let activation = try RecruitPlannerTests.action(.activate, initial, context, id: 1)
        var state = try #require(RecruitPlanner.applying(activation, to: initial, context: context))
        #expect(state.gold == 6 && state.board[0].entity.attack == 4)
        #expect(state.usedActivations == [1])
        state = try #require(RecruitPlanner.applying(RecruitPlannerTests.action(.buy, state, context, id: 3),
                                                   to: state, context: context))
        #expect(state.board[0].entity.attack == (golden ? 184 : 94))
        #expect(state.board[0].entity.health == (golden ? 135 : 70))
        #expect(state.hand[0].entity.attack == 90 && state.hand[0].entity.health == 65)
        state = try #require(RecruitPlanner.applying(RecruitPlannerTests.action(.buy, state, context, id: 4),
                                                   to: state, context: context))
        #expect(state.board[0].entity.attack == (golden ? 184 : 94))
        #expect(initial.board[0].entity.attack == 4 && initial.gold == 8 && request.shop.count == 2)
        #expect(RecruitPlanner.actions(state, context: context).allSatisfy { $0.kind != .activate })
    }

    @Test("Living Prison excludes changed effects, missing readiness, negative prices and double Activate gifts")
    func prisonBoundaries() throws {
        for mode in 0..<5 {
            var request = try Self.prisonRequest()
            if mode == 0 { request.recruit!.evaluationVersion = 10 }
            if mode == 1 { request.recruit!.activations = nil }
            if mode == 2 { request.recruit!.activations![1]!.cost = -1 }
            if mode == 3 { request.recruit!.definitions["BG36_180"]!.text = "Activate (1): Gain double the stats of the next minion you buy this turn." }
            if mode == 4 {
                let id = "BG36_MidGameEffect_test"
                request.board[0].entity.enchantments = [try AdvisorDiscardRegressionTests.gift(id)]
                Self.definition(id, text: "This minion's Activate triggers twice.", type: "ENCHANTMENT", request: &request)
            }
            let context = request.recruit!, state = RecruitState(request: request, context: context)
            #expect(RecruitPlanner.actions(state, context: context).allSatisfy { $0.kind != .activate })
        }
    }

    @Test("Observed pending Prisons consume a purchase separately and expire before combat")
    func prisonObservedPending() throws {
        var request = try Self.prisonRequest()
        request.board.append(S.boardMinion(2, "BG36_180_G", attack: 10, health: 12, golden: true))
        Self.definition("BG36_180_G", text: "Activate (1): Gain double the stats of the next minion you buy this turn.",
                        races: ["ELEMENTAL"], request: &request)
        request.recruit!.activations = [1: .init(ready: false, cost: 1), 2: .init(ready: false, cost: 1)]
        request.recruit!.pendingPrisonBuys = [1: true, 2: true]
        let context = request.recruit!, state = RecruitState(request: request, context: context)
        let buy = try RecruitPlannerTests.action(.buy, state, context, id: 3)
        let after = try #require(RecruitPlanner.applying(buy, to: state, context: context))
        #expect(after.board[0].entity.attack == 94 && after.board[0].entity.health == 70)
        #expect(after.board[1].entity.attack == 190 && after.board[1].entity.health == 142)
        #expect(after.pendingPrisonBuys == [1: false, 2: false])
        #expect(state.pendingPrisonBuys == [1: true, 2: true])
        let projected = RecruitEffects.combatProjection(state, context: context)
        #expect(projected.pendingPrisonBuys.values.allSatisfy { !$0 })
        #expect(projected.board == state.board, "An unconsumed activation grants no turn-end stats")
        request.recruit!.pendingPrisonBuys = nil
        let unknownContext = request.recruit!, unknown = RecruitState(request: request, context: unknownContext)
        #expect(RecruitPlanner.applying(buy, to: unknown, context: unknownContext) == nil)
        #expect(RecruitPlanner.search(request, context: unknownContext).limitations.contains {
            $0.contains("Living Prison") && $0.contains("pending")
        })
    }

    @Test("Casting a shop spell and stealing a minion leave Living Prison pending")
    func prisonAcquisitionKinds() throws {
        var request = try Self.prisonRequest()
        request.board.append(S.boardMinion(2, "BG36_354", attack: 2, health: 3))
        request.shop.append(S.spell(5, "BG28_503", cost: 1))
        Self.definition("BG36_354", text: "Activate (2): Steal the highest-Attack minion in the Tavern.", request: &request)
        Self.definition("BG28_503", text: "Give a minion +3 Health and Taunt.", type: "BATTLEGROUND_SPELL", request: &request)
        request.recruit!.activations = [1: .init(ready: false, cost: 1), 2: .init(ready: true, cost: 2)]
        request.recruit!.pendingPrisonBuys = [1: true]
        let context = request.recruit!, initial = RecruitState(request: request, context: context)
        let spell = try RecruitPlannerTests.action(.spell, initial, context, id: 5)
        var state = try #require(RecruitPlanner.applying(spell, to: initial, context: context))
        #expect(state.pendingPrisonBuys[1] == true && state.board[0].entity.attack == 4)
        let steal = try RecruitPlannerTests.action(.activate, state, context, id: 2)
        state = try #require(RecruitPlanner.applying(steal, to: state, context: context))
        #expect(state.hand.first?.entity.attack == 90 && state.pendingPrisonBuys[1] == true)
        let buy = try RecruitPlannerTests.action(.buy, state, context, id: 4)
        state = try #require(RecruitPlanner.applying(buy, to: state, context: context))
        #expect(state.board[0].entity.attack == 12 && state.board[0].entity.health == 17)
        #expect(state.pendingPrisonBuys[1] == false && initial.board[0].entity.health == 5)
    }

    @Test("Playing an observed held Prison preserves explicit pending state and keeps an absent tag unknown")
    func prisonHeldInstance() throws {
        for pending in [true, false, nil] as [Bool?] {
            var request = try Self.prisonRequest()
            request.hand = [request.board.removeFirst()]
            request.board = [S.boardMinion(2, "body", attack: 2, health: 3)]
            Self.definition("body", text: "", request: &request)
            request.recruit!.pendingPrisonBuys = pending.map { [1: $0] }
            let context = request.recruit!, initial = RecruitState(request: request, context: context)
            let play = try RecruitPlannerTests.action(.play, initial, context, id: 1)
            let played = try #require(RecruitPlanner.applying(play, to: initial, context: context))
            #expect(played.pendingPrisonBuys[1] == pending)
            let buy = try RecruitPlannerTests.action(.buy, played, context, id: 3)
            let bought = RecruitPlanner.applying(buy, to: played, context: context)
            if let pending {
                let prison = try #require(bought?.board.first { $0.entity.entityId == 1 })
                #expect(prison.entity.attack == (pending ? 94 : 4))
            } else { #expect(bought == nil) }
        }
    }

    @Test("An explicitly missing live Activate price blocks only Prison or Lionfish activation")
    func costObservation() throws {
        for lionfish in [false, true] {
            var request = try lionfish ? Self.lionfishRequest() : Self.prisonRequest()
            if !lionfish { request.recruit!.pendingPrisonBuys = [1: false] }
            let entityID = lionfish ? 2 : 1
            let capturedContext = request.recruit!, initial = RecruitState(request: request, context: capturedContext)
            let captured = try RecruitPlannerTests.action(.activate, initial, capturedContext, id: entityID)
            for observed in [nil, true, false] as [Bool?] {
                request.recruit!.activations![entityID]!.costObserved = observed
                let context = request.recruit!, state = RecruitState(request: request, context: context)
                let activates = RecruitPlanner.actions(state, context: context).filter { $0.kind == .activate }
                #expect(activates.isEmpty == (observed == false))
                #expect((RecruitPlanner.applying(captured, to: state, context: context) == nil) == (observed == false))
                let buy = try RecruitPlannerTests.action(.buy, state, context, id: lionfish ? 4 : 3)
                let bought = try #require(RecruitPlanner.applying(buy, to: state, context: context))
                #expect(RecruitEffects.combatProjection(bought, context: context).limitations.isEmpty)
                #expect(state.gold == 7 || state.gold == 8)
            }
        }
        // Existing families retain their captured/text fallback contract.
        var oldFamily = try Self.prisonRequest()
        oldFamily.board = [S.boardMinion(1, "BG36_354", attack: 2, health: 3)]
        Self.definition("BG36_354", text: "Activate (2): Steal the highest-Attack minion in the Tavern.", request: &oldFamily)
        oldFamily.recruit!.activations = [1: .init(ready: true, cost: 2, costObserved: false)]
        #expect(RecruitPlanner.actions(RecruitState(request: oldFamily, context: oldFamily.recruit!), context: oldFamily.recruit!)
            .contains { $0.kind == .activate })
    }

    @Test("Arcane Absorption uses the observed highest Health minion, rounds up, and targets Elementals only")
    func absorption() throws {
        var request = try RecruitPlannerTests.request(
            board: [S.boardMinion(1, "elemental", attack: 1645, health: 1387),
                    S.boardMinion(2, "beast", attack: 5, health: 5)],
            hand: [S.spell(3, "BG35_911")],
            shop: [S.shopMinion(4, attack: 218, health: 219, cardID: "source"),
                   S.shopMinion(5, attack: 500, health: 5, cardID: "lower")], gold: 0)
        request.recruit!.evaluationVersion = 11
        Self.definition("BG35_911", text: "Give a friendly Elemental half the stats of the highest-Health minion in the Tavern.",
                        type: "BATTLEGROUND_SPELL", request: &request)
        request.recruit!.definitions["elemental"]!.races = ["ELEMENTAL"]
        request.recruit!.definitions["beast"]!.races = ["BEAST"]
        let context = request.recruit!, state = RecruitState(request: request, context: context)
        let casts = RecruitPlanner.actions(state, context: context).filter { $0.kind == .spell }
        #expect(casts.count == 1 && casts.first?.targetID == 1)
        let step = try #require(casts.first)
        let after = try #require(RecruitPlanner.applying(step, to: state, context: context))
        #expect(after.board[0].entity.attack == 1754 && after.board[0].entity.health == 1497)
        #expect(after.board[1] == state.board[1] && after.shop == state.shop && after.hand.isEmpty)
        var invalid = step; invalid.targetID = 2
        #expect(RecruitPlanner.applying(invalid, to: state, context: context) == nil)
        request.shop[1].entity.health = 219; request.shop[1].entity.maxHealth = 219
        let tied = RecruitState(request: request, context: context)
        #expect(RecruitPlanner.actions(tied, context: context).allSatisfy { $0.kind != .spell },
                "a highest-Health tie with different Attack is an unknown outcome")
        request.shop = []
        #expect(RecruitPlanner.actions(RecruitState(request: request, context: context), context: context)
            .allSatisfy { $0.kind != .spell })
        request.recruit!.evaluationVersion = 10
        #expect(RecruitPlanner.actions(state, context: request.recruit!).allSatisfy { $0.kind != .spell })
    }

    @Test("Leyline Surfacer requires its generated Arcane Absorption definition and rewards known copies",
          arguments: [false, true])
    func leylineReward(golden: Bool) throws {
        let id = golden ? "BG35_881_G" : "BG35_881"
        var request = try RecruitPlannerTests.request(board: [S.boardMinion(1, "body", attack: 2, health: 3)],
            hand: [S.boardMinion(2, id, attack: golden ? 14 : 7, health: golden ? 10 : 5, golden: golden)], gold: 0)
        request.recruit!.evaluationVersion = 11
        Self.definition(id, text: golden ? "Battlecry and Deathrattle: Get 2 Arcane Absorptions."
                        : "Battlecry and Deathrattle: Get an Arcane Absorption.", races: ["ELEMENTAL"], request: &request)
        var context = request.recruit!, state = RecruitState(request: request, context: context)
        #expect(RecruitPlanner.actions(state, context: context).allSatisfy { $0.kind != .play })
        Self.definition("BG35_911", text: "Give a friendly Elemental half the stats of the highest-Health minion in the Tavern.",
                        type: "BATTLEGROUND_SPELL", request: &request)
        context = request.recruit!; state = RecruitState(request: request, context: context)
        let play = try RecruitPlannerTests.action(.play, state, context, id: 2)
        let after = try #require(RecruitPlanner.applying(play, to: state, context: context))
        #expect(after.hand.count == (golden ? 2 : 1) && after.hand.allSatisfy { $0.cardID == "BG35_911" && !$0.isMinion })
        #expect(after.board.last?.entity.entityId == 2 && state.hand.count == 1)
    }

    static func lionfishRequest(golden: Bool = false, wolf: Bool = true) throws -> AdvisorRequest {
        let id = golden ? "BG36_201_G" : "BG36_201"
        var board = [S.boardMinion(2, id, attack: golden ? 6 : 3, health: golden ? 8 : 4, golden: golden),
                     S.boardMinion(3, "spectator", attack: 1, health: 1)]
        if wolf { board.insert(S.boardMinion(1, "BG36_207", attack: 3, health: 6), at: 0) }
        var request = try RecruitPlannerTests.request(board: board,
            shop: [S.shopMinion(4, attack: 80, health: 80, cardID: "offered"), S.spell(5, "BG28_810")], gold: 7)
        request.recruit!.evaluationVersion = 11
        request.recruit!.activations = [2: .init(ready: true, cost: 2)]
        Self.definition(id, text: golden
            ? "Activate (2): Choose a card in the Tavern. Replace it with a Golden Fishbait for your left- most Beast to attack."
            : "Activate (2): Choose a card in the Tavern. Replace it with a Fishbait for your left-most Beast to attack.",
            races: ["BEAST"], request: &request)
        Self.definition("BG36_207", text: "Rally: Give your other minions +4/+1.", races: ["BEAST"], request: &request)
        for (token, amount, health) in [("BG36_205", 5, 1), ("BG36_205_G", 10, 2)] {
            Self.definition(token, text: "This can't gain stats. Deathrattle: Give the minion that killed this +\(amount)/+\(amount).",
                            races: ["BEAST"], request: &request)
            request.recruit!.definitions[token]!.attack = 0
            request.recruit!.definitions[token]!.health = health
            request.recruit!.definitions[token]!.mechanics = ["DEATHRATTLE"]
        }
        return request
    }

    @Test("Lionfish replaces any Tavern card, resolves Wolf Pup Rally, and feeds the leftmost Beast",
          arguments: [false, true])
    func lionfishKnownAttack(golden: Bool) throws {
        let request = try Self.lionfishRequest(golden: golden), context = request.recruit!
        let initial = RecruitState(request: request, context: context)
        let actions = RecruitPlanner.actions(initial, context: context).filter { $0.kind == .activate }
        #expect(actions.count == 2 && Set(actions.compactMap(\.targetID)) == [4, 5])
        let step = try #require(actions.first { $0.targetID == 5 })
        let after = try #require(RecruitPlanner.applying(step, to: initial, context: context))
        #expect(after.gold == 5 && after.shop.map(\.entity.entityId) == [4])
        #expect(after.board[0].entity.attack == (golden ? 13 : 8))
        #expect(after.board[0].entity.health == (golden ? 16 : 11))
        #expect(after.board[1].entity.attack == (golden ? 10 : 7))
        #expect(after.board[1].entity.health == (golden ? 9 : 5))
        #expect(after.board[2].entity.attack == 5 && after.board[2].entity.health == 2)
        #expect(after.usedActivations == [2] && initial.shop.count == 2 && request.gold == 7)
        #expect(RecruitPlanner.actions(after, context: context).allSatisfy { $0.kind != .activate })
        var invalid = step; invalid.targetID = 999
        #expect(RecruitPlanner.applying(invalid, to: initial, context: context) == nil)
    }

    @Test("Lionfish without Rally buffs only its attacker and skips a leftmost non-Beast")
    func lionfishPlainAttack() throws {
        var request = try Self.lionfishRequest(wolf: false)
        request.board.insert(S.boardMinion(6, "nonbeast", attack: 50, health: 50), at: 0)
        Self.definition("nonbeast", text: "After this attacks, gain +1/+1.", races: ["ELEMENTAL"], request: &request)
        let context = request.recruit!, initial = RecruitState(request: request, context: context)
        let step = try RecruitPlannerTests.action(.activate, initial, context, id: 2)
        let after = try #require(RecruitPlanner.applying(step, to: initial, context: context))
        #expect(after.board[0] == initial.board[0] && after.board[1].entity.attack == 8)
        #expect(after.board[1].entity.health == 9 && after.board[2] == initial.board[2])
    }

    @Test("Lionfish excludes missing tokens, changed definitions and unmodelled attack chains")
    func lionfishBoundaries() throws {
        for mode in 0..<9 {
            var request = try Self.lionfishRequest()
            if mode == 0 { request.recruit!.evaluationVersion = 10 }
            if mode == 1 { request.recruit!.definitions.removeValue(forKey: "BG36_205") }
            if mode == 2 { request.recruit!.definitions["BG36_205"]!.text = "Deathrattle: Give the minion that killed this +6/+6." }
            if mode == 3 { request.recruit!.definitions["BG36_201"]!.text = "Activate (1): Gain +5/+5." }
            if mode == 4 {
                Self.definition("spectator", text: "After a friendly minion attacks, your Beetles have +5/+5 this game.", request: &request)
            }
            if mode == 5 { request.recruit!.definitions["BG36_207"]!.text = "Rally: Get a random Beast." }
            if mode == 6 { request.board[0].entity.attack = 0 }
            if mode == 7 { request.recruit!.definitions.removeValue(forKey: "spectator") }
            if mode == 8 {
                request.recruit!.definitions["BG36_207"]!.text = ""
                request.recruit!.definitions["BG36_207"]!.mechanics = ["BACON_RALLY"]
            }
            let context = request.recruit!, state = RecruitState(request: request, context: context)
            #expect(RecruitPlanner.actions(state, context: context).allSatisfy { $0.kind != .activate })
            if mode == 4 {
                #expect(RecruitPlanner.search(request, context: context).limitations.contains { $0.contains("Lionfish") && $0.contains("attack") })
            }
        }
    }
}
