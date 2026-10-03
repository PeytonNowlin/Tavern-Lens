import Foundation
import Testing
import TavernEngine

@Suite("Recurring production recognition")
struct RecruitProductionTests {
    typealias S = AdvisorSynthetic

    struct Example: Sendable {
        let text: String
        let expected: Double
    }

    private static func fixture(_ text: String, id: String = "producer") throws
        -> (AdvisorCard, RecruitState, RecruitContext) {
        let card = S.boardMinion(1, id, attack: 2, health: 2)
        let board = [card, S.boardMinion(2, "filler-a", attack: 2, health: 2),
                     S.boardMinion(3, "filler-b", attack: 2, health: 2)]
        let hand = [S.shopMinion(10, attack: 1, health: 1, cardID: "BG20_GEM")]
        let request = try RecruitPlannerTests.request(board: board, hand: hand, texts: [id: text])
        let context = try #require(request.recruit)
        var state = RecruitState(request: request, context: context)
        state.input.playerBoard.player.globalInfo["BloodGemAttackBonus"] = 2
        state.input.playerBoard.player.globalInfo["BloodGemHealthBonus"] = 5
        return (card, state, context)
    }

    @Test("Literal wording retains branch priority and substring behavior", arguments: [
        Example(text: "", expected: 0),
        Example(text: "Unrecognized wording.", expected: 0),
        Example(text: "Battlecry: Get a Blood Gem.", expected: 0),
        Example(text: "When you sell this, get a coin.", expected: 0),
        Example(text: "Blood Gems played from your hand", expected: 3),
        Example(text: "Blood Gems played from your hand. Plays a Blood Gem on all.", expected: 3),
        Example(text: "Plays a Blood Gem on all. Blood Gems give an extra bonus.", expected: 6),
        Example(text: "Plays 2 Blood Gems on all", expected: 6),
        Example(text: "Blood Gems give an extra bonus. Get Gold.", expected: 12),
        Example(text: "Get a Blood Gem. At the end of your turn, get Gold.", expected: 6),
        Example(text: "At the end of your turn, get Gold. Sludge Corrosion.", expected: 3),
        Example(text: "At the end of your turn, buff your minions.", expected: 6),
        Example(text: "Small at the end of your turn", expected: 6),
        Example(text: "Get Gold. Sludge Corrosion.", expected: 3),
        Example(text: "Get a coin.", expected: 3),
        Example(text: "Sludge Corrosion", expected: 1.8),
        Example(text: "[x]<b>GeT</b>   a\nBlood Gem.", expected: 6),
    ])
    func wording(_ example: Example) throws {
        let (card, state, context) = try Self.fixture(example.text)
        #expect(abs(RecruitPlanner.production(card, state: state, context: context) - example.expected) < 0.000001)
    }

    @Test("Cycle cards still supply other gem engines and current hand supply is capped")
    func supply() throws {
        let (card, initial, original) = try Self.fixture("Blood Gems played from your hand")
        var state = initial, context = original
        context.definitions["filler-a"]?.text = "Battlecry: Get a Blood Gem."
        #expect(RecruitPlanner.production(state.board[1], state: state, context: context) == 0)
        #expect(RecruitPlanner.production(card, state: state, context: context) == 9)
        state.hand = []
        #expect(RecruitPlanner.production(card, state: state, context: context) == 6)
        state.hand = (10..<17).map { S.shopMinion($0, attack: 1, health: 1, cardID: "BG20_GEM") }
        #expect(RecruitPlanner.production(card, state: state, context: context) == 24)
        state.board.remove(at: 1)
        #expect(RecruitPlanner.production(card, state: state, context: context) == 21)
    }

    @Test("Gem bonus falls through when the current board has no gem wording")
    func gemBonusFallback() throws {
        let (card, initial, original) = try Self.fixture("Blood Gems give an extra bonus. Get Gold.")
        var context = original
        #expect(RecruitPlanner.production(card, state: initial, context: context) == 12)
        var state = initial
        state.board.removeFirst()
        #expect(RecruitPlanner.production(card, state: state, context: context) == 6)
        context.definitions[card.cardID]?.text = "Blood Gems give an extra bonus. At the end of your turn, gain strength."
        #expect(RecruitPlanner.production(card, state: state, context: context) == 3)
        state.board.append(card)
        #expect(RecruitPlanner.production(card, state: state, context: context) == 12)
    }

    @Test("Golden status, board size, bonuses and definition changes remain live inputs")
    func dynamicInputs() throws {
        let (normal, initial, original) = try Self.fixture("Plays 2 Blood Gems on all")
        var card = normal, state = initial, context = original
        #expect(RecruitPlanner.production(card, state: state, context: context) == 6)
        card.golden = true
        #expect(RecruitPlanner.production(card, state: state, context: context) == 12)
        state.board.append(S.boardMinion(4, "filler-a", attack: 2, health: 2))
        #expect(RecruitPlanner.production(card, state: state, context: context) == 18)
        state.input.playerBoard.player.globalInfo["BloodGemHealthBonus"] = 0
        #expect(RecruitPlanner.production(card, state: state, context: context) == 12)
        context.definitions[card.cardID]?.text = "Get Gold."
        #expect(RecruitPlanner.production(card, state: state, context: context) == 3)
        context.definitions[card.cardID]?.text = "Unrecognized new text."
        #expect(RecruitPlanner.production(card, state: state, context: context) == 0)
        #expect(RecruitPlanner.production(normal, state: initial, context: original) == 6)
    }

    @Test("Current end-of-turn repeaters and golden status multiply generic production")
    func endOfTurn() throws {
        let (normal, state, original) = try Self.fixture("At the end of your turn, buff your minions.")
        var context = original, card = normal
        #expect(RecruitPlanner.production(card, state: state, context: context) == 6)
        context.definitions["filler-a"]?.text = "Your end of turn effects trigger twice."
        #expect(RecruitPlanner.production(card, state: state, context: context) == 12)
        card.golden = true
        #expect(RecruitPlanner.production(card, state: state, context: context) == 24)
        context.definitions["filler-a"]?.text = "Your end of turn effects trigger three times."
        #expect(RecruitPlanner.production(card, state: state, context: context) == 36)
    }

    @Test("A zero card-specific override suppresses generic fallback under its policy")
    func overrideZero() throws {
        let (card, state, original) = try Self.fixture("Get Gold.", id: "BG34_858")
        var context = original
        context.evaluationVersion = 9
        #expect(RecruitPlanner.production(card, state: state, context: context) == 3)
        context.evaluationVersion = 10
        #expect(RecruitPlanner.production(card, state: state, context: context) == 0)
        context.evaluationVersion = 9
        #expect(RecruitPlanner.production(card, state: state, context: context) == 3)
    }

    @Test("Mechanics remain additive when cycle wording gives zero base production")
    func additiveMechanics() throws {
        let (normal, state, context) = try Self.fixture("Battlecry: Ignore. Deathrattle: Get a Fodder.")
        #expect(RecruitPlanner.production(normal, state: state, context: context) == 3)
        var reborn = normal; reborn.entity.reborn = true
        #expect(RecruitPlanner.production(reborn, state: state, context: context) == 6)
    }
}
