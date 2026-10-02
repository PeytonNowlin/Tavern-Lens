import Foundation
import Testing
import TavernEngine
@testable import BGIntel

@Suite("Elemental engine valuation")
struct AdvisorElementalValueTests {
    typealias S = AdvisorSynthetic

    @Test("Known recurring Elemental engines survive filler swaps without blocking decisive off-tribe strength")
    func preserveEngine() throws {
        let air = S.boardMinion(1, "BG34_858", attack: 6, health: 6)
        let ichoron = S.boardMinion(2, "BG31_812", attack: 4, health: 4)
        var request = try RecruitPlannerTests.request(board: [air, ichoron], gold: 7,
            texts: ["BG34_858": "After you spend 7 Gold, cast Easterly Winds. (7 left!)",
                    "BG31_812": "Divine Shield Whenever you play an Elemental, give it Divine Shield until next turn."])
        request.rollCost = 1
        var context = try #require(request.recruit)
        context.evaluationVersion = 10
        var winds = Card(id: "BG34_444", dbfId: 34, name: "Easterly Winds")
        winds.text = "After the Tavern is Refreshed this game, give a random minion in it +8/+8."
        context.definitions[winds.id] = winds
        var nomi = Card(id: "BG30_MagicItem_544", dbfId: 35, name: "Nomi Sticker")
        nomi.text = "After you play an Elemental, give Elementals in the Tavern +3/+2 this game."
        context.definitions[nomi.id] = nomi
        context.input.playerBoard.player.trinkets = [try JSONDecoder().decode(BattleTrinket.self, from: Data(
            #"{"cardId":"BG30_MagicItem_544","entityId":90,"scriptDataNum1":0,"scriptDataNum2":0,"scriptDataNum6":0}"#.utf8))]
        for id in [air.cardID, ichoron.cardID] { context.definitions[id]?.races = ["ELEMENTAL"] }
        let state = RecruitState(request: request, context: context)
        let baseline = RecruitPlanner.value(state, request: request, context: context).total
        let filler = S.boardMinion(3, "BG36_730", attack: 9, health: 9)
        var definition = Card(id: filler.cardID, dbfId: 36, name: "Trapped Clapper")
        definition.text = "Deathrattle: Add a Fodder to your next 3 Refreshes."; definition.races = ["DEMON"]
        context.definitions[filler.cardID] = definition
        var replaced = state; replaced.board[0] = filler
        #expect(RecruitPlanner.value(replaced, request: request, context: context).total < baseline)
        replaced.board[0].entity.attack = 50; replaced.board[0].entity.health = 50
        #expect(RecruitPlanner.value(replaced, request: request, context: context).total > baseline)
        #expect(state.board[0].entity.attack == 6 && state.shop.isEmpty)
        var old = context; old.evaluationVersion = 9
        #expect(RecruitElementalValue.production(air, state: state, context: old) == nil)
        var offered = state
        offered.shop = [filler]
        let buy = try RecruitPlannerTests.action(.buy, offered, context, id: 3)
        let unused = try #require(RecruitPlanner.applying(buy, to: offered, context: context))
        #expect(RecruitPlanner.value(unused, request: request, context: context).total
            < RecruitPlanner.value(offered, request: request, context: context).total,
            "Buying unused filler cannot make an otherwise identical continuation better")
        #expect(RecruitPlanner.value(unused, request: request, context: old).total
            > RecruitPlanner.value(offered, request: request, context: old).total,
            "Archived policy retains the captured hand-option overvaluation")
        var drift = context; drift.definitions[winds.id]?.text = "Give a random minion +80/+80."
        #expect(RecruitElementalValue.production(air, state: state, context: drift) == 0)
        var golden = air; golden.cardID = "BG34_858_G"; golden.entity.cardId = golden.cardID
        var goldenDefinition = Card(id: golden.cardID, dbfId: 37, name: "Golden Air Revenant")
        goldenDefinition.text = "After you spend 7 Gold, cast two Easterly Winds. (7 left!)"
        context.definitions[golden.cardID] = goldenDefinition
        let goldenProduction = try #require(RecruitElementalValue.production(golden, state: state, context: context))
        let normalProduction = try #require(RecruitElementalValue.production(air, state: state, context: context))
        #expect(goldenProduction > normalProduction)
        var spent = state; spent.gold = 0
        #expect(RecruitElementalValue.production(air, state: spent, context: context) == normalProduction)
    }

    @Test("Shield and Tavern scaling count only usable Elemental recipients, including all-type minions")
    func recipients() throws {
        let ichoron = S.boardMinion(1, "BG31_812", attack: 4, health: 4)
        let elemental = S.shopMinion(2, attack: 10, health: 10, cardID: "elemental")
        let outsider = S.shopMinion(3, attack: 50, health: 50, cardID: "outsider")
        let request = try RecruitPlannerTests.request(board: [ichoron], shop: [elemental, outsider], gold: 3,
            texts: ["BG31_812": "Divine Shield Whenever you play an Elemental, give it Divine Shield until next turn."])
        var context = try #require(request.recruit); context.evaluationVersion = 10
        context.definitions[elemental.cardID]?.races = ["ELEMENTAL"]
        context.definitions[outsider.cardID]?.races = ["DEMON"]
        let state = RecruitState(request: request, context: context)
        let supplied = try #require(RecruitElementalValue.production(ichoron, state: state, context: context))
        #expect(supplied > 0)
        var unavailable = state; unavailable.gold = 0
        #expect(RecruitElementalValue.production(ichoron, state: unavailable, context: context) == 0)
        unavailable = state; unavailable.shop[0].entity.divineShield = true
        #expect(RecruitElementalValue.production(ichoron, state: unavailable, context: context) == 0)
        unavailable = state; unavailable.shop = []; unavailable.hand = [elemental]
        unavailable.hand[0].entity.locked = true
        #expect(RecruitElementalValue.production(ichoron, state: unavailable, context: context) == 0)
        context.definitions[elemental.cardID]?.races = ["ALL"]
        #expect(RecruitElementalValue.production(ichoron, state: state, context: context) == supplied)
        var duplicate = state; var second = ichoron; second.entity.entityId = 4; duplicate.board.append(second)
        #expect(RecruitElementalValue.production(second, state: duplicate, context: context) == 0)
        let greasefire = S.boardMinion(5, "BG32_843", attack: 4, health: 4)
        var definition = Card(id: greasefire.cardID, dbfId: 38, name: "Blazing Greasefire")
        definition.text = "At the end of your turn, give Elementals in the Tavern +4/+4 this game."
        context.definitions[greasefire.cardID] = definition
        let growing = try #require(RecruitElementalValue.production(greasefire, state: state, context: context))
        var moreOutsiders = state; moreOutsiders.board.append(outsider); moreOutsiders.shop.append(outsider)
        #expect(RecruitElementalValue.production(greasefire, state: moreOutsiders, context: context) == growing)
        moreOutsiders.shop = [outsider]
        #expect(RecruitElementalValue.production(greasefire, state: moreOutsiders, context: context) == 0)
    }
}
