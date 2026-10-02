import Foundation
import HSData
import Testing
@testable import BGIntel

@Suite("Recruit card-effect table")
struct RecruitCardEffectsTests {
    typealias F = RecruitFixture

    static let prisonguard = F.definition("BG36_345", text: "Activate (1): Give another minion +3/+3.")
    static let prison = F.definition("BG36_180", text: "Activate (1): Gain the stats of the next minion you buy this turn.")
    static let ready = RecruitContext.Activation(ready: true, cost: 1, costObserved: true)

    @Test("Every card ID belongs to exactly one entry")
    func uniqueOwnership() {
        var owners: [String: String] = [:]
        for entry in RecruitCardEffects.all {
            for id in entry.cardIDs {
                #expect(owners[id] == nil, "\(id) is owned by both \(owners[id] ?? "") and \(entry)")
                owners[id] = "\(entry)"
            }
        }
    }

    @Test("An entry is absent before its policy version and answers from it on")
    func versionGate() throws {
        let board = [F.minion(1, "BG36_345"), F.minion(2, "body")]
        for (version, expected) in [(6, nil), (7, 1)] as [(Int, Int?)] {
            let (state, context) = try F.make(version: version, board: board, definitions: [Self.prisonguard],
                                              activations: [1: Self.ready])
            #expect(RecruitCardEffects.activationRecognized(board[0], context: context) == (expected != nil))
            let actions = RecruitCardEffects.activationActions(board[0], index: 0, state: state, context: context)
            #expect(actions?.count == expected, "version \(version)")
        }
    }

    @Test("A changed card text is not recognized, so the planner falls back to its generic rules")
    func changedText() throws {
        let card = F.minion(1, "BG36_345")
        let changed = F.definition("BG36_345", text: "Activate (1): Give another minion +4/+4.")
        let (state, context) = try F.make(version: 11, board: [card, F.minion(2, "body")], definitions: [changed],
                                          activations: [1: Self.ready])
        #expect(!RecruitCardEffects.activationRecognized(card, context: context))
        #expect(RecruitCardEffects.activationActions(card, index: 0, state: state, context: context) == nil)
    }

    @Test("Suspicious Prisonguard buffs the chosen minion and spends its Activate through the planner")
    func activateThroughPlanner() throws {
        let board = [F.minion(1, "BG36_345"), F.minion(2, "body", attack: 2, health: 3)]
        let (state, context) = try F.make(version: 11, board: board, gold: 3, definitions: [Self.prisonguard],
                                          activations: [1: Self.ready])
        let step = try #require(RecruitPlanner.actions(state, context: context).first { $0.kind == .activate })
        #expect(step.targetID == 2)
        let next = try #require(RecruitPlanner.applying(step, to: state, context: context))
        #expect(next.board[1].entity.attack == 5 && next.board[1].entity.health == 6)
        #expect(next.gold == 2 && next.usedActivations == [1])
        #expect(!RecruitPlanner.actions(next, context: context).contains { $0.kind == .activate })
    }

    @Test("Living Prison: an armed Prison gains the next bought minion's stats, then disarms")
    func prisonListener() throws {
        let board = [F.minion(1, "BG36_180", attack: 1, health: 1)]
        let shop = [F.minion(10, "body", attack: 4, health: 5)]
        let (state, context) = try F.make(version: 11, board: board, shop: shop, gold: 10, definitions: [Self.prison],
                                          activations: [1: Self.ready], pendingPrisonBuys: [1: false])
        let arm = try #require(RecruitPlanner.actions(state, context: context).first { $0.kind == .activate })
        let armed = try #require(RecruitPlanner.applying(arm, to: state, context: context))
        #expect(armed.pendingPrisonBuys[1] == true)
        let buy = try #require(RecruitPlanner.actions(armed, context: context).first { $0.kind == .buy })
        let bought = try #require(RecruitPlanner.applying(buy, to: armed, context: context))
        #expect(bought.board[0].entity.attack == 5 && bought.board[0].entity.health == 6)
        #expect(bought.pendingPrisonBuys[1] == false)
    }

    @Test("Living Prison with an unobserved pending state blocks buys and reports why")
    func prisonUnknown() throws {
        let board = [F.minion(1, "BG36_180")]
        let (state, context) = try F.make(version: 11, board: board, shop: [F.minion(10, "body")],
                                          definitions: [Self.prison], activations: [1: Self.ready])
        #expect(RecruitCardEffects.activationLimitation(board[0], state: state, context: context)?.contains("Living Prison") == true)
        var copy = state
        #expect(!RecruitCardEffects.afterBuy(F.minion(10, "body"), state: &copy, context: context))
    }

    @Test("Generated definitions are captured whatever the policy version")
    func generated() {
        #expect(Set(RecruitCardEffects.generated(for: [F.minion(1, "BG36_201_G")])) == ["BG36_205", "BG36_205_G"])
        #expect(RecruitCardEffects.generated(for: [F.minion(1, "BG35_881")]) == ["BG35_911"])
        #expect(RecruitCardEffects.generated(for: [F.minion(1, "body")]).isEmpty)
    }

    @Test("Trinkets: an exact text is supported, a changed one is unsupported, an unowned one falls through")
    func trinkets() throws {
        let scale = "Whenever a friendly Dragon attacks, give it Divine Shield. (3 times per combat.)"
        let (_, exact) = try F.make(version: 11, definitions: [F.definition("BG32_MagicItem_363", type: "BATTLEGROUND_TRINKET", text: scale)])
        #expect(RecruitCardEffects.trinketSupported("BG32_MagicItem_363", context: exact) == true)
        let (_, changed) = try F.make(version: 11, definitions: [F.definition("BG32_MagicItem_363", type: "BATTLEGROUND_TRINKET", text: "Changed.")])
        #expect(RecruitCardEffects.trinketSupported("BG32_MagicItem_363", context: changed) == false)
        #expect(RecruitCardEffects.trinketSupported("BG00_unowned", context: exact) == nil)
        let (_, mallet) = try F.make(version: 4, definitions: [F.definition("BG36_MagicItem_302", type: "BATTLEGROUND_TRINKET", text: "Something else.")])
        #expect(RecruitCardEffects.trinketSupported("BG36_MagicItem_302", context: mallet) == nil)
    }

    @Test("Arcane Absorption only targets an Elemental and halves the highest-Health Tavern minion, rounding up")
    func absorption() throws {
        let spell = F.spell(5, "BG35_911")
        let board = [F.minion(1, "elemental"), F.minion(2, "beast")]
        let shop = [F.minion(10, "big", attack: 7, health: 9)]
        let definitions = [
            F.definition("BG35_911", type: "BATTLEGROUND_SPELL", text: RecruitArcaneAbsorption.text),
            F.definition("elemental", text: "", races: ["ELEMENTAL"]), F.definition("beast", text: "", races: ["BEAST"]),
        ]
        let (state, context) = try F.make(version: 11, board: board, hand: [spell], shop: shop, definitions: definitions)
        #expect(RecruitCardEffects.spellTargetAllowed(spell, target: 1, state: state, context: context))
        #expect(!RecruitCardEffects.spellTargetAllowed(spell, target: 2, state: state, context: context))
        guard case .buff(4, 5, all: false)? = RecruitCardEffects.spellEffect(spell, state: state, context: context) else {
            Issue.record("expected a +4/+5 single-target buff"); return
        }
    }
}
