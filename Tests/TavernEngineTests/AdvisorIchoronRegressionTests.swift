import Foundation
import Testing
import TavernEngine

@Suite("Ichoron played minion regressions")
struct AdvisorIchoronRegressionTests {
    typealias S = AdvisorSynthetic

    static func request(golden: Bool = false, tribes: [String]? = ["ELEMENTAL"]) throws -> AdvisorRequest {
        let id = golden ? "BG31_812_G" : "BG31_812"
        var ichoron = S.boardMinion(1, id, attack: golden ? 6 : 3, health: golden ? 2 : 1, golden: golden)
        ichoron.entity.divineShield = true
        var request = try RecruitPlannerTests.request(board: [ichoron],
            hand: [S.boardMinion(2, "played", attack: 2, health: 3)],
            texts: [id: golden
                ? "Divine Shield Whenever you play an Elemental, give it Divine Shield."
                : "Divine Shield Whenever you play an Elemental, give it Divine Shield until next turn."])
        request.recruit?.evaluationVersion = 9
        request.recruit?.definitions["played"]?.races = tribes
        for (id, text) in [("BG31_812e", "Divine Shield until next turn."), ("BG31_812e2", "Divine Shield")] {
            var definition = Card(id: id, dbfId: id == "BG31_812e" ? 101 : 102, name: "Protected")
            definition.type = "ENCHANTMENT"; definition.text = text
            request.recruit?.definitions[id] = definition
        }
        return request
    }

    static func play(_ request: AdvisorRequest) throws -> RecruitState? {
        let context = try #require(request.recruit), state = RecruitState(request: request, context: context)
        let step = try RecruitPlannerTests.action(.play, state, context, id: 2)
        return RecruitPlanner.applying(step, to: state, context: context)
    }

    @Test("Normal and golden Ichoron protect played Elementals and all-tribe minions through combat")
    func shieldsAndSummons() throws {
        let tribeCases: [[String]?] = [["ELEMENTAL"], ["ALL"], ["MURLOC"], nil]
        for golden in [false, true] {
            for tribes in tribeCases {
                var request = try Self.request(golden: golden, tribes: tribes)
                request.recruit?.definitions["played"]?.text = "Battlecry: Summon a 1/1 Cat."
                var token = Card(id: "BG_CFM_315t", dbfId: 103, name: "Synthetic summoned Elemental")
                token.type = "MINION"; token.races = ["ELEMENTAL"]; token.attack = 1; token.health = 1
                request.recruit?.definitions[token.id] = token
                let after = try #require(try Self.play(request))
                let played = try #require(after.board.first { $0.entity.entityId == 2 })
                let getsShield = tribes == ["ELEMENTAL"] || tribes == ["ALL"]
                let enchantment = golden ? "BG31_812e2" : "BG31_812e"
                #expect(played.entity.divineShield == getsShield)
                #expect(played.entity.enchantments.map(\.cardId) == (getsShield ? [enchantment] : []))
                let summoned = try #require(after.board.first { $0.cardID == token.id })
                #expect(!summoned.entity.divineShield && summoned.entity.enchantments.isEmpty)
                #expect(after.board[0].entity.divineShield && after.board[0].entity.enchantments.isEmpty)
                if getsShield {
                    #expect(played.entity.enchantments[0].originEntityId == -1)
                    #expect(summoned.entity.entityId == -2, "attachments and generated minions use distinct synthetic IDs")
                }
                let projection = RecruitEffects.combatProjection(after, context: request.recruit!)
                #expect(projection.limitations.isEmpty)
                #expect(projection.combatInput.playerBoard.board.first { $0.entityId == 2 }?.divineShield == getsShield)
                #expect(after.input.playerBoard.player.globalInfo["BattlecriesTriggeredThisGame"] == 1)
                #expect(!request.hand[0].entity.divineShield && request.hand[0].entity.enchantments.isEmpty)
            }
        }
    }

    @Test("Old policies, changed definitions and removed Ichorons retain their correct boundaries")
    func compatibilityAndSource() throws {
        var request = try Self.request()
        request.recruit?.evaluationVersion = 8
        #expect(try Self.play(request) == nil)
        request.recruit?.evaluationVersion = 9
        request.recruit?.definitions["BG31_812"]?.text = "Divine Shield Whenever you play an Elemental, give it Taunt."
        #expect(try Self.play(request) == nil)
        request = try Self.request()
        request.recruit?.definitions.removeValue(forKey: "BG31_812e")
        #expect(try Self.play(request) == nil)
        request = try Self.request()
        request.recruit?.definitions["BG31_812e"]?.text = "Divine Shield for two turns."
        #expect(try Self.play(request) == nil)

        request = try Self.request()
        request.board.append(S.boardMinion(3, "filler", attack: 1, health: 1))
        let context = request.recruit!, initial = RecruitState(request: request, context: context)
        let sell = try RecruitPlannerTests.action(.sell, initial, context, id: 1)
        let sold = try #require(RecruitPlanner.applying(sell, to: initial, context: context))
        let play = try RecruitPlannerTests.action(.play, sold, context, id: 2)
        let unprotected = try #require(RecruitPlanner.applying(play, to: sold, context: context))
        #expect(unprotected.board.first { $0.entity.entityId == 2 }?.entity.divineShield == false)

        request = try Self.request()
        request.board = []
        request.hand = [S.boardMinion(2, "BG31_812", attack: 3, health: 1)]
        request.hand[0].entity.divineShield = true
        let newlyPlayed = try #require(try Self.play(request))
        #expect(newlyPlayed.board[0].entity.divineShield && newlyPlayed.board[0].entity.enchantments.isEmpty,
                "a newly played Ichoron does not trigger its own play")

        request = try Self.request()
        request.hand[0].entity.divineShield = true
        let shielded = try #require(try Self.play(request))
        #expect(shielded.board.first { $0.entity.entityId == 2 }?.entity.divineShield == true)
    }
}
