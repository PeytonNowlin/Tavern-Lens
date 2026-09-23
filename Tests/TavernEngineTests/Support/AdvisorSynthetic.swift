import Foundation
import Testing
import TavernEngine

/// Advisor requests built on the committed turn-11 combat input (no private logs), and a stub
/// scorer whose odds are a plain function of the board, so rankings can be predicted exactly.
enum AdvisorSynthetic {
    static func minion(_ id: Int, _ cardID: String = "BG36_102", attack: Int, health: Int, taunt: Bool = false) -> BattleEntity {
        // BattleEntity has no public memberwise initializer; it's the simulator's JSON anyway.
        let json: [String: Any] = [
            "entityId": id, "cardId": cardID, "attack": attack, "health": health, "maxHealth": health, "taunt": taunt,
            "divineShield": false, "poisonous": false, "venomous": false, "reborn": false, "stealth": false,
            "windfury": false, "locked": false, "enchantments": [], "scriptDataNum1": 0, "scriptDataNum2": 0,
            "scriptDataNum3": 0, "scriptDataNum4": 0, "scriptDataNum5": 0, "scriptDataNum6": 0, "tags": [String: Int](),
        ]
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(BattleEntity.self, from: JSONSerialization.data(withJSONObject: json))
    }

    static func shopMinion(_ id: Int, attack: Int, health: Int, cost: Int? = nil, cardID: String = "BG36_106") -> AdvisorCard {
        AdvisorCard(cardID: cardID, kind: .minion, cost: cost, tier: 3, entity: minion(id, cardID, attack: attack, health: health))
    }

    static func spell(_ id: Int, _ cardID: String, cost: Int? = 1) -> AdvisorCard {
        AdvisorCard(cardID: cardID, kind: .tavernSpell, cost: cost, entity: minion(id, cardID, attack: 0, health: 0))
    }

    /// The turn-11 local side with its first `boardCount` minions (all 7 by default), against the real opponent.
    static func request(
        boardCount: Int = 7, shop: [AdvisorCard] = [], hand: [AdvisorCard] = [], gold: Int = 10, tier: Int = 5,
        levelCost: Int? = 7, rollCost: Int? = 1, canFreeze: Bool = true, seenTurn: Int? = 10,
        source: OddsPreviewRequest.OpponentSource = .combatStart, hasData: Bool = true
    ) throws -> AdvisorRequest {
        var input = try CombatGoldens.input(CombatGoldens.fullGameTurn11)
        input.playerBoard.board = Array(input.playerBoard.board.prefix(boardCount))
        input.playerBoard.player.hand = hand.map(\.entity)
        let preview = OddsPreviewRequest(
            gameSeed: 1, bgTurn: 11, opponentPlayerID: 7, opponentSeenTurn: hasData ? seenTurn : nil,
            opponentSource: hasData ? source : nil, input: hasData ? input : nil
        )
        let board = input.playerBoard.board.map {
            AdvisorCard(cardID: $0.cardId, kind: .minion, cost: nil, tier: 3, entity: $0)
        }
        return AdvisorRequest(
            preview: preview, gold: gold, tier: tier, board: board, hand: hand, shop: shop, levelCost: levelCost,
            rollCost: rollCost, canFreeze: canFreeze, shopFrozen: false
        )
    }

    /// Odds from the local board's total stats: `base` equity at `baseline` total stats, one
    /// percentage point per `perPoint` stats more; `position` weighs the leftmost minion's stats
    /// that many times more (so placement matters); `lethal` is the loss that kills.
    struct Stub: Sendable {
        var baseline: Int
        var base = 50.0
        var perPoint = 2.0
        var leftmostWeight = 1.0
        var lethal = 0.0
        var lethalAbove: Int? = nil
        var delay: Duration? = nil

        func strength(_ input: BattleInput) -> Double {
            input.playerBoard.board.enumerated().reduce(0.0) { total, pair in
                let stats = Double(pair.element.attack + pair.element.health)
                return total + (pair.offset == 0 ? stats * leftmostWeight : stats)
            }
        }

        func odds(_ input: BattleInput, simulations: Int) -> CombatOdds {
            let won = min(100, max(0, base + (strength(input) - Double(baseline)) / perPoint))
            let lethalRisk = lethalAbove.map { strength(input) < Double($0) ? lethal : 0 } ?? 0
            return CombatOdds(
                won: won, tied: 0, lost: 100 - won, lostLethal: min(lethalRisk, 100 - won), averageDamageWon: 6,
                averageDamageLost: 8, simulations: simulations, isFinal: true
            )
        }
    }

    /// Records every call the stub scorer gets.
    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [(input: BattleInput, simulations: Int, seed: UInt32)] = []
        func add(_ input: BattleInput, _ simulations: Int, _ seed: UInt32) { lock.withLock { entries.append((input, simulations, seed)) } }
        var all: [(input: BattleInput, simulations: Int, seed: UInt32)] { lock.withLock { entries } }
    }

    static func simulate(_ stub: Stub, calls: Calls = Calls()) -> AdvisorEvaluation.Simulate {
        { input, budget, seed in
            calls.add(input, budget.simulations, seed)
            if let delay = stub.delay { try await Task.sleep(for: delay) }
            return stub.odds(input, simulations: budget.simulations)
        }
    }

    /// The baseline's stats for `request` (so the stub puts it at `base`).
    static func baseline(_ request: AdvisorRequest) -> Int {
        Int(Stub(baseline: 0).strength(request.preview.input!))
    }

    static let plan = AdvisorPlan(seed: 42, simulations: 400, refineSimulations: 800, refinedGroups: 2)
}
