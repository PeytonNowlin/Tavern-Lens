import Foundation
import HSData
@testable import BGIntel

/// Recruit states on the committed turn-11 combat input, with every player-side attachment
/// cleared so only the cards a test names are present.
enum RecruitFixture {
    static let combatInput = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "TavernEngineTests/Golden/Combat/full-game-turn-11.input.json")

    static func entity(_ id: Int, _ cardID: String, attack: Int, health: Int) -> BattleEntity {
        // BattleEntity has no public memberwise initializer; it's the simulator's JSON anyway.
        let json: [String: Any] = [
            "entityId": id, "cardId": cardID, "attack": attack, "health": health, "maxHealth": health, "taunt": false,
            "divineShield": false, "poisonous": false, "venomous": false, "reborn": false, "stealth": false,
            "windfury": false, "locked": false, "enchantments": [], "scriptDataNum1": 0, "scriptDataNum2": 0,
            "scriptDataNum3": 0, "scriptDataNum4": 0, "scriptDataNum5": 0, "scriptDataNum6": 0, "tags": [String: Int](),
        ]
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(BattleEntity.self, from: JSONSerialization.data(withJSONObject: json))
    }

    static func minion(_ id: Int, _ cardID: String, attack: Int = 2, health: Int = 2, cost: Int? = 3) -> AdvisorCard {
        AdvisorCard(cardID: cardID, kind: .minion, cost: cost, tier: 3, entity: entity(id, cardID, attack: attack, health: health))
    }

    static func spell(_ id: Int, _ cardID: String, cost: Int? = 1) -> AdvisorCard {
        AdvisorCard(cardID: cardID, kind: .tavernSpell, cost: cost, entity: entity(id, cardID, attack: 0, health: 0))
    }

    static func definition(_ id: String, type: String = "MINION", text: String, races: [String]? = nil,
                           attack: Int? = nil, health: Int? = nil, mechanics: [String]? = nil) -> Card {
        var card = Card(id: id, dbfId: id.utf8.reduce(1) { $0 &* 31 &+ Int($1) } & 0xFFFFF, name: id)
        card.type = type; card.text = text; card.races = races
        card.attack = attack; card.health = health; card.mechanics = mechanics
        return card
    }

    /// Cards without a definition get a vanilla minion one.
    static func make(version: Int, board: [AdvisorCard] = [], hand: [AdvisorCard] = [], shop: [AdvisorCard] = [],
                     gold: Int = 10, definitions: [Card] = [], trinkets: [String] = [],
                     activations: [Int: RecruitContext.Activation] = [:],
                     pendingPrisonBuys: [Int: Bool] = [:]) throws -> (RecruitState, RecruitContext) {
        var input = try JSONDecoder().decode(BattleInput.self, from: Data(contentsOf: combatInput))
        input.playerBoard.board = board.map(\.entity)
        input.playerBoard.player.hand = hand.map(\.entity)
        input.playerBoard.player.heroPowers = []; input.playerBoard.player.secrets = []
        input.playerBoard.player.questEntities = []; input.playerBoard.player.globalInfo = [:]
        input.playerBoard.player.trinkets = trinkets.enumerated().map {
            BattleTrinket(cardId: $0.element, entityId: 900 + $0.offset, scriptDataNum1: 0, scriptDataNum2: 0, scriptDataNum6: 0)
        }
        var known: [String: Card] = [:]
        for card in board + hand + shop { known[card.cardID] = definition(card.cardID, text: "") }
        for card in definitions { known[card.id] = card }
        var context = RecruitContext(input: input, definitions: known)
        context.evaluationVersion = version
        context.activations = activations
        context.pendingPrisonBuys = pendingPrisonBuys
        let preview = OddsPreviewRequest(gameSeed: 1, bgTurn: 11, opponentPlayerID: 7, opponentSeenTurn: nil,
                                         opponentSource: nil, input: nil)
        let request = AdvisorRequest(preview: preview, gold: gold, tier: 5, board: board, hand: hand, shop: shop)
        return (RecruitState(request: request, context: context), context)
    }
}
