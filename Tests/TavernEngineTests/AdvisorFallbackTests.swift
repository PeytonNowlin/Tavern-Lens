import Foundation
import Testing
import TavernEngine

@Suite("Cautious recruit fallback")
struct AdvisorFallbackTests {
    typealias S = AdvisorSynthetic
    static let missingTrigger = "Unmodelled play trigger on the board"

    static func request() throws -> AdvisorRequest {
        let board = [S.boardMinion(1, "filler", attack: 3, health: 3),
                     S.boardMinion(2, "scaler", attack: 1, health: 1),
                     S.boardMinion(3, "unknown", attack: 60, health: 60)]
            + (4...7).map { S.boardMinion($0, "body\($0)", attack: 20 + $0, health: 20 + $0) }
        var request = try RecruitPlannerTests.request(board: board,
            shop: [S.shopMinion(20, attack: 40, health: 40, cardID: "upgrade")], gold: 2,
            texts: ["scaler": "At the end of your turn, give your other minions +3/+3.",
                    "unknown": "Whenever you play a minion, gain a random Bonus Keyword."])
        request.recruit!.evaluationVersion = 9
        return request
    }

    static func buys(_ suggestion: AdvisorSuggestion, _ id: String = "upgrade") -> Bool {
        switch suggestion.action {
        case .buy(_, let card, _), .swap(_, let card, _, _): return card == id
        default: return suggestion.continuation?.contains("Buy \(id)") == true
        }
    }

    static func sells(_ suggestion: AdvisorSuggestion, _ id: String) -> Bool {
        switch suggestion.action {
        case .sell(_, let card), .swap(_, _, _, let card): return card == id
        default: return suggestion.continuation?.contains("Sell \(id)") == true
        }
    }

    @Test("An unknown play trigger permits a cautious funded replacement while protecting scaling")
    func legalContinuation() throws {
        let request = try Self.request(), context = request.recruit!
        let original = request
        let suggestions = RecruitFallback.suggestions(request, context: context, limitations: [Self.missingTrigger])
        let purchase = try #require(suggestions.first { Self.buys($0) })
        #expect(Self.sells(purchase, "filler"))
        #expect(!suggestions.contains { Self.sells($0, "scaler") })
        #expect(purchase.continuation?.contains("Buy upgrade") == true)
        #expect(purchase.continuation?.contains("Play upgrade") == true)
        #expect(request.board.count == AdvisorRequest.boardLimit && request.gold + AdvisorRequest.sellValue == 3)
        #expect(purchase.confidence == .low && purchase.odds == nil)
        #expect(purchase.limitations?.contains(Self.missingTrigger) == true)
        #expect(purchase.limitations?.contains { $0.localizedCaseInsensitiveContains("not verified") } == true)
        #expect(!purchase.reason.contains("%"))
        #expect(request == original && context == original.recruit)
    }

    @Test("Known consume value, survival and unavailable actions remain protected")
    func boundaries() throws {
        var consume = try Self.request()
        let enforcer = "BG34_500_G"
        consume.board[1] = S.boardMinion(2, enforcer, attack: 8, health: 10, golden: true)
        var definition = Card(id: enforcer, dbfId: 126925, name: "Flaming Enforcer")
        definition.type = "MINION"
        definition.text = "At the end of your turn, consume the highest-Health minion in the Tavern to gain double its stats."
        consume.recruit!.definitions[enforcer] = definition
        consume.shop[0].entity.attack = 200
        consume.shop[0].entity.health = 200
        consume.shop[0].entity.maxHealth = 200
        consume.gold = 4
        consume.rollCost = 1
        let protected = RecruitFallback.suggestions(consume, context: consume.recruit!, limitations: [Self.missingTrigger])
        #expect(!protected.contains { Self.buys($0) })
        #expect(!protected.contains { if case .roll = $0.action { return true }; return false })

        for health in [1, 15] {
            var wounded = try Self.request()
            wounded.shop = []; wounded.tier = 3; wounded.levelCost = 1
            wounded.recruit!.input.playerBoard.player.hpLeft = health
            let suggestions = RecruitFallback.suggestions(wounded, context: wounded.recruit!, limitations: [])
            #expect(!suggestions.contains { if case .level = $0.action { return true }; return false })
            #expect(!suggestions.contains { $0.continuation?.contains { $0.hasPrefix("Level ") } == true })
        }

        for boundary in ["hand full", "pending choice", "missing definition", "unknown Battlecry"] {
            var unavailable = try Self.request()
            switch boundary {
            case "hand full": unavailable.hand = (100..<110).map { S.spell($0, "held\($0)") }
            case "pending choice": unavailable.recruit!.pendingChoice = true
            case "missing definition": unavailable.recruit!.definitions.removeValue(forKey: "upgrade")
            default:
                unavailable.recruit!.definitions["upgrade"]!.text = "Battlecry: Transform a friendly minion into a random minion."
                unavailable.recruit!.definitions["upgrade"]!.mechanics = ["BATTLECRY"]
            }
            let suggestions = RecruitFallback.suggestions(unavailable, context: unavailable.recruit!, limitations: [])
            #expect(!suggestions.contains { Self.buys($0) }, "\(boundary) cannot invent a legal purchase")
            if boundary == "pending choice" { #expect(suggestions.isEmpty) }
        }
    }

    @Test("Policy 9 fills an unchecked gap without overriding combat rejection or inventing funding")
    func policyAndCombatBoundary() async throws {
        var request = try Self.request()
        request.preview.input = nil
        request.preview.opponentSeenTurn = nil
        request.lobby = []
        var plan = S.plan; plan.version = 8
        let old = try await AdvisorEvaluation.run(request, plan: plan, simulate: S.simulate(.init(baseline: 0)))
        #expect(old.advice.suggestions.isEmpty)
        plan.version = 9
        let current = try await AdvisorEvaluation.run(request, plan: plan, simulate: S.simulate(.init(baseline: 0)))
        #expect(current.evaluations == 0)
        #expect(current.advice.suggestions.contains { Self.buys($0) })
        #expect(current.advice.suggestions.allSatisfy { $0.confidence == .low && $0.odds == nil })

        var unsafe = try RecruitPlannerTests.request(board: [S.boardMinion(1, "body", attack: 2, health: 2)],
            shop: [S.shopMinion(20, attack: 30, health: 30, cardID: "upgrade")])
        unsafe.recruit!.evaluationVersion = 9
        #expect(RecruitFallback.suggestions(unsafe, context: unsafe.recruit!, limitations: []).contains { Self.buys($0) })
        var stub = S.Stub(baseline: 4)
        stub.minionPoints = [20: -100]
        stub.minionLethal = [20: 100]
        let checked = try await AdvisorEvaluation.run(unsafe, plan: plan, simulate: S.simulate(stub))
        #expect(checked.evaluations > 0)
        #expect(checked.advice.suggestions.map(\.action) == [.keep], "estimated strength cannot restore a lethally unsafe purchase")

        var impossible = try Self.request()
        impossible.gold = 1; impossible.shop[0].cost = 10
        impossible.tier = 6; impossible.levelCost = 0
        #expect(impossible.gold + impossible.board.count * AdvisorRequest.sellValue < 10)
        let suggestions = RecruitFallback.suggestions(impossible, context: impossible.recruit!, limitations: [])
        #expect(!suggestions.contains { Self.buys($0) || Self.sells($0, "filler") })
        #expect(!suggestions.contains { if case .level = $0.action { return true }; return false })
    }
}
