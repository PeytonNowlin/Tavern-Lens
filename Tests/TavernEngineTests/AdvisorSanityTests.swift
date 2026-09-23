import Foundation
import Testing
import TavernEngine

/// The sanity layer, one rule at a time, on synthetic states the blended score alone would get
/// wrong: each state's clearly bad suggestion is an improvement by the score, and the rule takes
/// it out (or moves it down) and says so in `Advice.sanity`. The bookmarked cases are checked
/// against the rules in `AdvisorTuningTests` and `AdvisorFixtureTests`.
@Suite("Advisor sanity layer")
struct AdvisorSanityTests {
    typealias S = AdvisorSynthetic

    static func run(_ request: AdvisorRequest, _ stub: S.Stub, weights: AdvisorWeights = .standard) async throws -> Advice {
        try await AdvisorEvaluation.run(request, plan: S.plan.with(weights: weights), simulate: S.simulate(stub)).advice
    }

    static func fired(_ advice: Advice, _ rule: AdvisorSanityRule, on candidate: String) -> Bool {
        advice.sanity?.contains(AdvisorSanityNote(rule: rule, candidate: candidate)) == true
    }

    static func shows(_ advice: Advice, _ group: String) -> Bool {
        advice.suggestions.contains { $0.action.group == group }
    }

    @Test("Every rule is documented, and only survivalFirst downranks")
    func documented() throws {
        for rule in AdvisorSanityRule.allCases {
            #expect(!rule.summary.isEmpty)
            #expect(rule.effect == (rule == .survivalFirst ? .downrank : .veto))
        }
        let doc = try String(contentsOf: Self.scoringDoc, encoding: .utf8)
        for rule in AdvisorSanityRule.allCases { #expect(doc.contains("`\(rule.rawValue)`"), "\(rule) in the doc") }
    }

    static let scoringDoc = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "docs/advisor/scoring.md")

    @Test("unaffordable: never suggest what the gold can't pay for")
    func unaffordable() throws {
        let request = try S.request(shop: [S.shopMinion(901, attack: 9, health: 9, cost: 5)], gold: 4, levelCost: 7)
        let context = AdvisorSanity.Context(
            request: request, weights: .standard, baseLethalRisk: 0, baseSimulations: 1000, shopHasImprovement: false,
            freezeKeeps: 1
        )
        let option = { (action: AdvisorAction) in AdvisorSanity.Option(action: action, combatGain: 20, lethalRisk: 0, simulations: 1000) }
        #expect(AdvisorSanity.veto(option(.buy(shop: 0, cardID: "BG36_106", place: 0)), in: context) == .unaffordable)
        #expect(AdvisorSanity.veto(option(.level(cost: 7, toTier: 6)), in: context) == .unaffordable)
        #expect(AdvisorSanity.veto(option(.roll(cost: 1)), in: context) == nil)
    }

    @Test("lastMinion: selling the only minion is never suggested, even when the score likes it")
    func lastMinion() async throws {
        let only = S.boardMinion(800, "BG36_102", attack: 5, health: 5)
        let request = try S.request(board: [only])
        var stub = AdvisorSyntheticTests.stub(request)
        stub.minionPoints = [800: -30]  // the stub's board does better without it
        let advice = try await Self.run(request, stub)
        #expect(Self.fired(advice, .lastMinion, on: "sell:b0"))
        #expect(!Self.shows(advice, "sell:b0"))
    }

    @Test("newLethalRisk: a buy that wins more but can get the player killed is vetoed")
    func newLethalRisk() async throws {
        let request = try S.request(boardCount: 5, shop: [S.shopMinion(901, attack: 40, health: 40)], gold: 3)
        var stub = AdvisorSyntheticTests.stub(request)
        stub.minionLethal = [901: 30]  // +40% win, but 10% of the time a lethal loss
        let advice = try await Self.run(request, stub)
        #expect(Self.fired(advice, .newLethalRisk, on: "buy:s0@5"))
        #expect(!Self.shows(advice, "buy:s0"))
        // The same buy without the risk is the top suggestion.
        let safe = try await Self.run(request, AdvisorSyntheticTests.stub(request))
        #expect(safe.suggestions.first?.action.group == "buy:s0")
    }

    @Test("survivalFirst: at a real risk of dying, a buy that cuts it goes before levelling")
    func survivalFirst() async throws {
        let request = try S.request(boardCount: 5, shop: [S.shopMinion(901, attack: 2, health: 2)], gold: 10, tier: 4, levelCost: 7)
        var stub = AdvisorSyntheticTests.stub(request, base: 30)
        stub.lethal = 30
        stub.lethalAbove = stub.baseline + 1  // any buy takes the lethal risk away
        var weights = AdvisorWeights.standard
        weights.tierTurnValue = 30  // levelling now scores 44, the buy 32
        let advice = try await Self.run(request, stub, weights: weights)
        #expect(advice.suggestions.map(\.action.group).prefix(2) == ["buy:s0", "level"])
        #expect(Self.fired(advice, .survivalFirst, on: "level"))
        #expect(advice.suggestions[1].confidence == .low, "moved down: low confidence")
        #expect(advice.suggestions[1].gain > advice.suggestions[0].gain)
        #expect(advice.status == .recommendation, "a sanity reorder isn't a close call")
        // Without the danger, levelling comes first.
        var calm = stub
        calm.lethal = 0
        let safe = try await Self.run(request, calm, weights: weights)
        #expect(safe.suggestions.first?.action.group == "level")
    }

    @Test("keepPairs: selling one of a pair is vetoed unless the combat gain is big")
    func keepPairs() async throws {
        let board = [
            S.boardMinion(801, "BG36_110", attack: 3, health: 3), S.boardMinion(802, "BG36_110", attack: 3, health: 3),
            S.boardMinion(803, "BG36_102", attack: 10, health: 10),
        ]
        let request = try S.request(board: board)
        var stub = AdvisorSyntheticTests.stub(request)
        stub.minionPoints = [801: -10]  // selling it gains about 8
        let advice = try await Self.run(request, stub)
        #expect(Self.fired(advice, .keepPairs, on: "sell:b0"))
        #expect(!Self.shows(advice, "sell:b0"))
        // Gaining 24 is worth half a triple.
        stub.minionPoints = [801: -25]
        let big = try await Self.run(request, stub)
        #expect(big.suggestions.first?.action.group == "sell:b0")
        #expect(big.sanity == nil)
    }

    @Test("keepBuildCore: selling a core card of the build is vetoed unless the combat gain is big")
    func keepBuildCore() async throws {
        let board = [S.boardMinion(801, "BG36_997", attack: 3, health: 3), S.boardMinion(803, "BG36_102", attack: 10, health: 10)]
        let request = try S.request(builds: [AdvisorBlendTests.discard()], board: board)
        var stub = AdvisorSyntheticTests.stub(request)
        stub.minionPoints = [801: -14]  // selling it gains about 12, less the build's 6
        let advice = try await Self.run(request, stub)
        #expect(Self.fired(advice, .keepBuildCore, on: "sell:b0"))
        #expect(!Self.shows(advice, "sell:b0"))
        stub.minionPoints = [801: -30]
        let big = try await Self.run(request, stub)
        #expect(big.suggestions.first?.action.group == "sell:b0")
    }

    @Test("rollPastImprovement: no refresh while the shop has an upgrade")
    func rollPastImprovement() async throws {
        let upgrade = try S.request(boardCount: 5, shop: [S.shopMinion(901, attack: 6, health: 6)], gold: 10, levelCost: nil)
        let advice = try await Self.run(upgrade, AdvisorSyntheticTests.stub(upgrade, base: 10))
        #expect(Self.fired(advice, .rollPastImprovement, on: "roll"))
        #expect(!Self.shows(advice, "roll") && Self.shows(advice, "buy:s0"))
        // A shop with nothing: the refresh is suggested (behind on the board, 10% win).
        let empty = try S.request(boardCount: 5, shop: [S.shopMinion(901, attack: 0, health: 1)], gold: 10, levelCost: nil)
        let roll = try await Self.run(empty, AdvisorSyntheticTests.stub(empty, base: 10))
        #expect(roll.suggestions.first?.action.group == "roll")
    }

    @Test("freezeForNothing: no freeze when nothing in the shop is worth keeping")
    func freezeForNothing() throws {
        let request = try S.request(shop: [S.shopMinion(901, attack: 1, health: 1)])
        let option = AdvisorSanity.Option(action: .freeze, combatGain: 0, lethalRisk: 0, simulations: 1000)
        func context(_ keeps: Double) -> AdvisorSanity.Context {
            AdvisorSanity.Context(
                request: request, weights: .standard, baseLethalRisk: 0, baseSimulations: 1000, shopHasImprovement: false,
                freezeKeeps: keeps
            )
        }
        #expect(AdvisorSanity.veto(option, in: context(0)) == .freezeForNothing)
        #expect(AdvisorSanity.veto(option, in: context(8)) == nil)
    }

    @Test("Shown advice is checked against the rules: a sane list passes, a bad one is caught")
    func violations() throws {
        let request = try S.request(gold: 3, board: [S.boardMinion(800, "BG36_102", attack: 5, health: 5)])
        func suggestion(_ action: AdvisorAction, lethal: Double = 0) -> AdvisorSuggestion {
            AdvisorSuggestion(
                rank: 1, action: action, targets: action.targets, reason: "x", confidence: .medium,
                odds: AdvisorOdds(won: 50, tied: 0, lost: 50, lethalRisk: lethal, averageDamageDealt: 0, averageDamageTaken: 0,
                                  simulations: 1000),
                gain: 5, terms: AdvisorTerms(combat: 5)
            )
        }
        let base = AdvisorOdds(won: 50, tied: 0, lost: 50, lethalRisk: 0, averageDamageDealt: 0, averageDamageTaken: 0, simulations: 1000)
        let sane = Advice(status: .recommendation, baseline: base, suggestions: [suggestion(.roll(cost: 1))])
        #expect(AdvisorSanity.violations(sane, request: request).isEmpty)
        let bad = Advice(status: .recommendation, baseline: base, suggestions: [
            suggestion(.sell(board: 0, cardID: "BG36_102")), suggestion(.move(board: 0, cardID: "BG36_102", to: 0), lethal: 20),
        ])
        #expect(AdvisorSanity.violations(bad, request: request).map(\.rule) == [.lastMinion, .newLethalRisk])
    }
}
