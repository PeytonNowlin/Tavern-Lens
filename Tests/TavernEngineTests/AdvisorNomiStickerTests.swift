import Foundation
import Testing
import TavernEngine
@testable import BGIntel

@Suite("Nomi Sticker observed shop increments")
struct AdvisorNomiStickerTests {
    typealias S = AdvisorSynthetic
    static let lesser = "BG30_MagicItem_544"
    static let greater = "BG30_MagicItem_544t"

    static func request(_ id: String) throws -> AdvisorRequest {
        var request = try RecruitPlannerTests.request(
            board: [S.boardMinion(1, "brann", attack: 2, health: 4)],
            hand: [S.boardMinion(2, "played", attack: 10, health: 10),
                   S.boardMinion(3, "all", attack: 4, health: 4),
                   S.boardMinion(4, "summoner", attack: 1, health: 1)],
            shop: [S.shopMinion(10, attack: 60, health: 50, cardID: "elemental"),
                   S.shopMinion(11, attack: 40, health: 40, cardID: "shopAll"),
                   S.shopMinion(12, attack: 80, health: 56, cardID: "neutral"),
                   S.spell(13, "spell", cost: 1)],
            texts: ["brann": "Your Battlecries trigger twice.", "played": "Battlecry: Gain 1 Gold.",
                    "summoner": "Battlecry: Summon a 1/1 Cat.", "spell": "Gain 1 Gold."])
        for id in [Self.lesser, Self.greater] {
            var definition = Card(id: id, dbfId: id == Self.lesser ? 112392 : 115235, name: "Nomi Sticker")
            definition.type = "BATTLEGROUND_TRINKET"
            definition.text = id == Self.lesser
                ? "[x]After you play an Elemental,\ngive Elementals in the Tavern\n+3/+2 this game."
                : "After you play an Elemental, give Elementals in the Tavern +5/+5 this game."
            request.recruit!.definitions[id] = definition
        }
        for id in ["played", "elemental"] { request.recruit!.definitions[id]!.races = ["ELEMENTAL"] }
        for id in ["all", "shopAll"] { request.recruit!.definitions[id]!.races = ["ALL"] }
        request.recruit!.definitions["summoner"]!.races = ["BEAST"]
        var token = Card(id: "BG_CFM_315t", dbfId: 200, name: "Synthetic summoned Elemental")
        token.type = "MINION"; token.races = ["ELEMENTAL"]; token.attack = 1; token.health = 1
        request.recruit!.definitions[token.id] = token
        request.recruit!.definitions["elemental"]!.attack = 2
        request.recruit!.definitions["elemental"]!.health = 2
        request.recruit!.input.playerBoard.player.trinkets = [try AdvisorTrinketRegressionTests.trinket(id)]
        request.recruit!.input.playerBoard.player.globalInfo["ElementalAttackBuff"] = 120
        request.recruit!.input.playerBoard.player.globalInfo["ElementalHealthBuff"] = 90
        request.recruit!.evaluationVersion = 10
        return request
    }

    static func apply(_ kind: RecruitStep.Kind, _ id: Int? = nil, to state: RecruitState,
                      context: RecruitContext) throws -> RecruitState {
        let step = try RecruitPlannerTests.action(kind, state, context, id: id)
        return try #require(RecruitPlanner.applying(step, to: state, context: context))
    }

    @Test("Each played Elemental buffs only remaining shop Elementals once", arguments: [lesser, greater])
    func playBuyAndSummon(_ id: String) throws {
        let request = try Self.request(id), context = request.recruit!
        let attack = id == Self.lesser ? 3 : 5, health = id == Self.lesser ? 2 : 5
        let initial = RecruitState(request: request, context: context)
        let pendingInitial = RecruitNomiSticker.pendingShopBuff(in: initial, context: context)
        #expect(pendingInitial.attack == 0 && pendingInitial.health == 0)
        #expect(!RecruitPlanner.search(request, context: context, budget: .init(depth: 0))
            .limitations.contains("Unmodelled trinket: Nomi Sticker"))
        var state = try Self.apply(.play, 2, to: initial, context: context)
        let pendingFirst = RecruitNomiSticker.pendingShopBuff(in: state, context: context)
        #expect(pendingFirst.attack == attack && pendingFirst.health == health)
        #expect(state.gold == 5, "Brann repeats the Battlecry, not the after-play trinket")
        #expect(state.shop[0].entity.attack == 60 + attack && state.shop[0].entity.health == 50 + health)
        #expect(state.shop[0].entity.maxHealth == 50 + health)
        #expect(state.shop[1].entity.attack == 40 + attack && state.shop[1].entity.health == 40 + health)
        #expect(state.shop[2] == initial.shop[2] && state.shop[3] == initial.shop[3])
        #expect(state.board.first { $0.entity.entityId == 2 }?.entity.attack == 10)
        state = try Self.apply(.play, 3, to: state, context: context)
        let pendingSecond = RecruitNomiSticker.pendingShopBuff(in: state, context: context)
        #expect(pendingSecond.attack == 2 * attack && pendingSecond.health == 2 * health)
        #expect(state.shop[0].entity.attack == 60 + 2 * attack && state.shop[0].entity.health == 50 + 2 * health)
        let beforeSummons = state.shop
        state = try Self.apply(.play, 4, to: state, context: context)
        let pendingSummons = RecruitNomiSticker.pendingShopBuff(in: state, context: context)
        #expect(pendingSummons.attack == 2 * attack && pendingSummons.health == 2 * health)
        #expect(state.board.filter { $0.cardID == "BG_CFM_315t" }.count == 2)
        #expect(state.shop == beforeSummons, "A non-Elemental play and summoned Elementals do not trigger Nomi")
        state = try Self.apply(.buy, 10, to: state, context: context)
        #expect(state.shop[0] == beforeSummons[1], "Buying does not trigger Nomi")
        state = try Self.apply(.play, 10, to: state, context: context)
        let pendingThird = RecruitNomiSticker.pendingShopBuff(in: state, context: context)
        #expect(pendingThird.attack == 3 * attack && pendingThird.health == 3 * health)
        let bought = try #require(state.board.first { $0.entity.entityId == 10 })
        #expect(bought.entity.attack == 60 + 2 * attack && bought.entity.health == 50 + 2 * health)
        #expect(state.shop[0].entity.attack == 40 + 3 * attack && state.shop[0].entity.health == 40 + 3 * health)
        #expect(state.input.playerBoard.player.globalInfo["ElementalAttackBuff"] == 120)
        #expect(state.input.playerBoard.player.globalInfo["ElementalHealthBuff"] == 90)
        #expect(state.input.playerBoard.player.trinkets == context.input.playerBoard.player.trinkets)
        #expect(request.shop[0].entity.attack == 60 && request.hand[0].entity.attack == 10)
    }

    @Test("Stacked variants change a later consume while unknown outcomes and old policies stay bounded")
    func consumptionAndCompatibility() throws {
        var request = try Self.request(Self.lesser)
        let enforcer = "BG34_500"
        request.board = [S.boardMinion(20, enforcer, attack: 4, health: 5)]
        request.hand = [request.hand[0]]
        request.rollCost = 1
        request.recruit!.definitions["played"]!.text = nil
        request.recruit!.definitions["played"]!.mechanics = nil
        var definition = Card(id: enforcer, dbfId: 126924, name: "Flaming Enforcer")
        definition.type = "MINION"
        definition.text = "At the end of your turn, consume the highest-Health minion in the Tavern to gain its stats."
        request.recruit!.definitions[enforcer] = definition
        request.recruit!.input.playerBoard.player.trinkets.append(try AdvisorTrinketRegressionTests.trinket(Self.greater))
        let context = request.recruit!, initial = RecruitState(request: request, context: context)
        let baseline = RecruitEffects.combatProjection(initial, context: context)
        #expect(baseline.board[0].entity.attack == 84 && baseline.board[0].entity.health == 61)
        let played = try Self.apply(.play, 2, to: initial, context: context)
        let projection = RecruitEffects.combatProjection(played, context: context)
        #expect(projection.board[0].entity.attack == 72 && projection.board[0].entity.health == 62)
        #expect(projection.limitations.isEmpty)
        var repeated = played
        repeated.board.append(S.boardMinion(21, enforcer, attack: 4, health: 5))
        let unresolved = RecruitEffects.combatProjection(repeated, context: context)
        #expect(unresolved.limitations.contains("Multiple Tavern consumes need unknown shop replacements"))
        #expect(unresolved.board.last?.entity.attack == 4 && unresolved.board.last?.entity.health == 5)
        let rolled = try Self.apply(.roll, to: played, context: context)
        #expect(rolled.terminal && rolled.shop.isEmpty && RecruitPlanner.actions(rolled, context: context).isEmpty)
        #expect(rolled.limitations.contains("Next shop unknown; refresh is a search decision, not a promised hit"))

        var old = context
        old.evaluationVersion = 9
        let pendingOld = RecruitNomiSticker.pendingShopBuff(in: played, context: old)
        #expect(pendingOld.attack == 0 && pendingOld.health == 0)
        #expect(RecruitPlanner.search(request, context: old, budget: .init(depth: 0))
            .limitations.contains("Unmodelled trinket: Nomi Sticker"))
        #expect(try Self.apply(.play, 2, to: initial, context: old).shop == initial.shop)
        let play = try RecruitPlannerTests.action(.play, initial, context, id: 2)
        for id in [Self.lesser, Self.greater, "elemental"] {
            var missing = context
            missing.definitions.removeValue(forKey: id)
            #expect(RecruitPlanner.applying(play, to: initial, context: missing) == nil)
        }
        var changed = context
        changed.definitions[Self.lesser]!.text = "After you play an Elemental, give Elementals in the Tavern +9/+9 this game."
        #expect(RecruitPlanner.applying(play, to: initial, context: changed) == nil)
        #expect(RecruitPlanner.search(request, context: changed, budget: .init(depth: 0))
            .limitations.contains("Unmodelled trinket: Nomi Sticker"))
    }
}
