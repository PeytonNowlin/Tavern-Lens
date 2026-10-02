import Foundation
import Testing
import TavernEngine

@Suite("Fruit Vendor Activate")
struct AdvisorFruitVendorTests {
    typealias S = AdvisorSynthetic
    static let bananaID = "BG28_897"

    static func request(golden: Bool = false) throws -> AdvisorRequest {
        let id = golden ? "BG36_346_G" : "BG36_346"
        var request = try RecruitPlannerTests.request(
            board: [S.boardMinion(1, "body", attack: 2, health: 1),
                    S.boardMinion(2, id, attack: 3, health: 3, golden: golden)], gold: 1,
            texts: [id: "<b>Activate (1):</b> Get \(golden ? 4 : 2)\nTavern Dish Bananas."])
        var banana = Card(id: bananaID, dbfId: 105752, name: "Tavern Dish Banana")
        banana.type = "BATTLEGROUND_SPELL"; banana.cost = 1; banana.text = "Give a minion +2/+2."
        request.recruit!.definitions[bananaID] = banana
        request.recruit!.evaluationVersion = 8
        request.recruit!.activations = [2: .init(ready: true, cost: 1)]
        return request
    }

    @Test("Activate generates the known Bananas and their free hand casts apply every buff", arguments: [false, true])
    func activateAndCast(golden: Bool) throws {
        let request = try Self.request(golden: golden), context = request.recruit!
        let original = RecruitState(request: request, context: context)
        let activation = try RecruitPlannerTests.action(.activate, original, context, id: 2)
        var state = try #require(RecruitPlanner.applying(activation, to: original, context: context))
        let count = golden ? 4 : 2
        #expect(state.gold == 0 && state.usedActivations == [2])
        #expect(state.hand.count == count && state.hand.allSatisfy { $0.cardID == Self.bananaID && !$0.isMinion })
        #expect(Set(state.hand.map { $0.entity.entityId }).count == count)
        #expect(activation.action.targets == [.init(.board, 1)])
        #expect(!activation.title.lowercased().contains("discard"))
        #expect(try JSONDecoder().decode(AdvisorAction.self, from: JSONEncoder().encode(activation.action)) == activation.action)
        #expect(!state.terminal && state.unknownRewards == 0)
        for _ in 0..<count {
            let cast = try #require(RecruitPlanner.actions(state, context: context).first { $0.kind == .spell && $0.targetID == 1 })
            state = try #require(RecruitPlanner.applying(cast, to: state, context: context))
        }
        #expect(state.hand.isEmpty && state.gold == 0)
        #expect(state.board[0].entity.attack == 2 + 2 * count && state.board[0].entity.health == 1 + 2 * count)
        #expect(state.board[1].entity.attack == 3 && state.board[1].entity.health == 3)
        #expect(state.input.playerBoard.player.globalInfo["GoldSpentThisGame"] == 1)
        #expect(state.input.playerBoard.player.globalInfo["SpellsCastThisGame"] == count)
        #expect(state.input.playerBoard.player.globalInfo["TavernSpellsCastThisGame"] == count)
        #expect(RecruitPlanner.actions(state, context: context).allSatisfy { $0.kind != .activate })
        #expect(RecruitPlanner.value(state, request: request, context: context).total
                > RecruitPlanner.value(original, request: request, context: context).total)
    }

    @Test("Fruit Vendor respects archived coverage, readiness, gold, hand capacity and known token data")
    func boundaries() throws {
        for mode in 0..<6 {
            var request = try Self.request()
            switch mode {
            case 0: request.recruit!.evaluationVersion = 7
            case 1: request.recruit!.activations?[2]?.ready = false
            case 2: request.gold = 0
            case 3: request.hand = (10..<19).map { S.spell($0, "held\($0)") }
            case 4: request.recruit!.definitions.removeValue(forKey: Self.bananaID)
            default: request.recruit!.definitions["BG36_346"]!.text = "Activate (1): Get 3 Tavern Dish Bananas."
            }
            let context = request.recruit!, state = RecruitState(request: request, context: context)
            #expect(RecruitPlanner.actions(state, context: context).allSatisfy { $0.kind != .activate })
        }
    }
}
