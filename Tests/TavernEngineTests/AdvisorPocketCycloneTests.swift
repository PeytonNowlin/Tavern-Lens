import Foundation
import Testing
import TavernEngine

@Suite("Pocket Cyclone observed shop buffs")
struct AdvisorPocketCycloneTests {
    typealias S = AdvisorSynthetic
    static let lesser = "BG35_MagicItem_850"
    static let greater = "BG35_MagicItem_850t"

    static func request(_ id: String) throws -> AdvisorRequest {
        var request = try RecruitPlannerTests.request(
            board: [S.boardMinion(1, "body", attack: 2, health: 2)],
            shop: [S.shopMinion(2, attack: 152, health: 152, cardID: "observed")])
        request.recruit!.definitions["observed"]!.attack = 4
        request.recruit!.definitions["observed"]!.health = 4
        var definition = Card(id: id, dbfId: id == lesser ? 130888 : 131329, name: "Pocket Cyclone")
        definition.type = "BATTLEGROUND_TRINKET"
        definition.text = id == lesser
            ? "Cast Easterly Winds.\nAt the start of each turn, cast it again."
            : "[x]Cast Easterly Winds four\ntimes. At the start of each\nturn, cast it twice more."
        request.recruit!.definitions[id] = definition
        request.recruit!.input.playerBoard.player.trinkets = [try AdvisorTrinketRegressionTests.trinket(id)]
        request.recruit!.input.playerBoard.player.globalInfo["TavernSpellsCastThisGame"] = 32
        request.recruit!.evaluationVersion = 9
        return request
    }

    @Test("Exact variants unlock observed buy/play plans without recasting buffs", arguments: [lesser, greater])
    func observedBuffAndCoverage(_ id: String) throws {
        let request = try Self.request(id), context = request.recruit!
        let result = RecruitPlanner.search(request, context: context, budget: .init(depth: 2))
        #expect(!result.limitations.contains("Unmodelled trinket: Pocket Cyclone"))
        let plan = try #require(result.plans.first { $0.state.board.contains { $0.entity.entityId == 2 } })
        #expect(plan.projection.limitations.isEmpty)
        let bought = try #require(plan.projection.board.first { $0.entity.entityId == 2 })
        #expect(bought.entity.attack == 152 && bought.entity.health == 152)
        #expect(plan.projection.board.first?.entity.attack == 2)
        #expect(plan.projection.input.playerBoard.player.globalInfo == context.input.playerBoard.player.globalInfo)
        #expect(plan.projection.input.playerBoard.player.trinkets == context.input.playerBoard.player.trinkets)
        #expect(plan.projection.hand.isEmpty)

        var archived = context
        archived.evaluationVersion = 8
        #expect(RecruitPlanner.search(request, context: archived, budget: .init(depth: 0))
            .limitations.contains("Unmodelled trinket: Pocket Cyclone"))
        var changed = context
        changed.definitions[id]!.text = "Cast Easterly Winds three times."
        #expect(RecruitPlanner.search(request, context: changed, budget: .init(depth: 0))
            .limitations.contains("Unmodelled trinket: Pocket Cyclone"))
    }

    @Test("Pocket Cyclone leaves refresh outcomes and repeated Tavern consumes unresolved")
    func unknownShopBoundaries() throws {
        var request = try Self.request(Self.greater)
        request.rollCost = 1
        var context = request.recruit!
        let original = RecruitState(request: request, context: context)
        let roll = try RecruitPlannerTests.action(.roll, original, context)
        let rolled = try #require(RecruitPlanner.applying(roll, to: original, context: context))
        #expect(rolled.terminal && rolled.shop.isEmpty)
        #expect(RecruitPlanner.actions(rolled, context: context).isEmpty)
        #expect(RecruitEffects.combatProjection(rolled, context: context).limitations
            .contains("Next shop unknown; refresh is a search decision, not a promised hit"))

        let enforcer = "BG34_500"
        request.board = [S.boardMinion(10, enforcer, attack: 4, health: 5),
                         S.boardMinion(11, enforcer, attack: 4, health: 5)]
        var definition = Card(id: enforcer, dbfId: 126924, name: "Flaming Enforcer")
        definition.type = "MINION"
        definition.text = "At the end of your turn, consume the highest-Health minion in the Tavern to gain its stats."
        context.definitions[enforcer] = definition
        let projection = RecruitEffects.combatProjection(RecruitState(request: request, context: context), context: context)
        #expect(projection.limitations.contains("Multiple Tavern consumes need unknown shop replacements"))
        #expect(projection.board[0].entity.attack == 156 && projection.board[0].entity.health == 157)
        #expect(projection.board[1].entity.attack == 4 && projection.board[1].entity.health == 5)
    }
}
