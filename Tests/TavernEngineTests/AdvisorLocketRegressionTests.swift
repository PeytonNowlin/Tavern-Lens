import Foundation
import Testing
import TavernEngine

@Suite("Lovely Locket recruit regressions")
struct AdvisorLocketRegressionTests {
    typealias S = AdvisorSynthetic
    static let locket = "BG36_MagicItem_211"
    static let text = "After you cast a spell on a friendly minion, this casts it on another friendly minion."

    static func request(count: Int = 2, spell: String = "buff", text: String = "Give a minion +4/+5.") throws -> AdvisorRequest {
        let board = (1...count).map { S.boardMinion($0, "body\($0)", attack: 2 * $0, health: 2 * $0 + 1) }
        var request = try RecruitPlannerTests.request(board: board,
            hand: [S.spell(20, spell), S.spell(21, "BG28_810", cost: 0)],
            shop: [S.shopMinion(30, attack: 12, health: 12, cardID: "upgrade")],
            texts: [spell: text])
        request.recruit?.evaluationVersion = 8
        request.recruit?.input.playerBoard.player.trinkets = [try AdvisorTrinketRegressionTests.trinket(locket)]
        var definition = Card(id: locket, dbfId: 100, name: "Lovely Locket")
        definition.text = Self.text
        request.recruit?.definitions[locket] = definition
        return request
    }

    static func cast(_ request: AdvisorRequest, id: Int = 20) throws -> RecruitState {
        let context = try #require(request.recruit), state = RecruitState(request: request, context: context)
        let step = try #require(RecruitPlanner.actions(state, context: context).first {
            $0.kind == .spell && $0.entityID == id && ($0.targetID == 1 || $0.targetID == nil)
        })
        return try #require(RecruitPlanner.applying(step, to: state, context: context))
    }

    @Test("A sole other friendly receives the copy after hero triggers without replaying hero counters")
    func exactCopyAndOrder() throws {
        for (spell, text, targetAttack, targetHealth, otherAttack, otherHealth, tavernCount) in [
            ("buff", "Give a minion +4/+5.", 6, 8, 10, 13, 10),
            ("BG20_GEM", "Give a minion +1/+1.", 5, 7, 9, 12, 9),
            ("set", "Set a minion's stats to 7/8.", 7, 8, 7, 8, 10)
        ] {
            var request = try Self.request(spell: spell, text: text)
            request.recruit?.definitions["body2"]?.text = "After you cast a spell, gain +2/+3."
            request.recruit?.input.playerBoard.player.globalInfo = [
                "SpellsCastThisGame": 11, "TavernSpellsCastThisGame": 9,
                "BloodGemAttackBonus": 2, "BloodGemHealthBonus": 3
            ]
            let after = try Self.cast(request)
            #expect(after.board[0].entity.attack == targetAttack && after.board[0].entity.health == targetHealth)
            #expect(after.board[1].entity.attack == otherAttack && after.board[1].entity.health == otherHealth)
            #expect(after.input.playerBoard.player.globalInfo["SpellsCastThisGame"] == 12)
            #expect(after.input.playerBoard.player.globalInfo["TavernSpellsCastThisGame"] == tavernCount)
            #expect(after.gold == 3 && after.hand.map(\.entity.entityId) == [21])
            #expect(after.limitations.isEmpty && !after.terminal)
        }

        let alone = try Self.cast(Self.request(count: 1))
        #expect(alone.board[0].entity.attack == 6 && alone.limitations.isEmpty)
        var dead = try Self.request()
        dead.board[1].entity.health = 0
        let noLivingOther = try Self.cast(dead)
        #expect(noLivingOther.board[1].entity.attack == 4 && noLivingOther.board[1].entity.health == 0)

        var gift = try Self.request()
        let giftID = "BG36_MidGameEffect_000t74e"
        gift.board[1].entity.enchantments = [try JSONDecoder().decode(BattleEnchantment.self,
            from: Data(#"{"cardId":"BG36_MidGameEffect_000t74e","originEntityId":90,"timing":0}"#.utf8))]
        var definition = Card(id: giftID, dbfId: 101, name: "Sharpened Sword")
        definition.text = "Whenever you play a card, gain +3 Attack."
        gift.recruit?.definitions[giftID] = definition
        #expect(try Self.cast(gift).board[1].entity.attack == 11, "the copied cast does not play a second card")
    }

    @Test("Random copies limit only their cast; ordinary actions, old policies and changed text stay honest")
    func scopedLimitations() throws {
        var request = try Self.request(count: 3)
        let context = request.recruit!, initial = RecruitState(request: request, context: context)
        let random = try Self.cast(request)
        #expect(random.terminal && random.limitations.contains { $0.contains("Lovely Locket") && $0.contains("random") })
        #expect(random.board[1].entity.attack == 4 && random.board[2].entity.attack == 6)
        #expect(RecruitPlanner.actions(random, context: context).isEmpty)
        let search = RecruitPlanner.search(request, context: context)
        #expect(search.baseline.projection.limitations.isEmpty)
        // Search keeps only the best continuation per first action. With the buff in
        // hand, a buy can continue into that uncertain cast and correctly inherit its limit.
        var purchaseRequest = request
        purchaseRequest.hand.removeAll { $0.entity.entityId == 20 }
        let purchases = RecruitPlanner.search(purchaseRequest, context: context)
        #expect(purchases.plans.contains { $0.state.steps.first?.kind == .buy && $0.projection.limitations.isEmpty })
        let coin = try Self.cast(request, id: 21)
        #expect(coin.gold == 4 && coin.limitations.isEmpty && !coin.terminal)
        for kind in [RecruitStep.Kind.buy, .sell, .move] {
            let step = try RecruitPlannerTests.action(kind, initial, context)
            let next = try #require(RecruitPlanner.applying(step, to: initial, context: context))
            #expect(next.limitations.isEmpty)
            #expect(RecruitEffects.combatProjection(next, context: context).limitations.isEmpty)
        }

        request.recruit?.evaluationVersion = 7
        let archived = RecruitPlanner.search(request, context: request.recruit!)
        #expect(archived.limitations.contains { $0.contains("Unmodelled trinket: Lovely Locket") })
        #expect(try Self.cast(request).board[1].entity.attack == 4)
        request.recruit?.evaluationVersion = 8
        request.recruit?.definitions[Self.locket]?.text = "After you cast a spell, cast it twice."
        #expect(RecruitPlanner.search(request, context: request.recruit!).limitations.contains { $0.contains("Unmodelled trinket") })

        var duplicate = try Self.request()
        duplicate.recruit?.input.playerBoard.player.trinkets.append(try AdvisorTrinketRegressionTests.trinket(Self.locket))
        let duplicates = try Self.cast(duplicate)
        #expect(duplicates.terminal && duplicates.limitations.contains { $0.contains("Multiple Lovely Lockets") })
        var repeated = try Self.request(spell: "BG20_GEM", text: "Give a minion +1/+1.")
        repeated.recruit?.definitions["body2"]?.text = "Blood Gems played from your hand cast an extra time."
        let repeats = try Self.cast(repeated)
        #expect(repeats.terminal && repeats.limitations.contains { $0.contains("repeated Blood Gems") })
        for id in ["BG32_431", "BG34_PreMadeChamp_076", "BG35_883"] {
            var reactive = try Self.request(spell: "BG20_GEM", text: "Give a minion +1/+1.")
            reactive.board[1] = S.boardMinion(2, id, attack: 4, health: 5)
            let limited = try Self.cast(reactive)
            #expect(limited.terminal && limited.limitations.contains { $0.contains("Lovely Locket") })
        }
    }
}
