import Foundation
import HSData
import BGState
import EntityStore
import PowerParser

/// Everything the planner needs, including the exact patch's effect text. No live lookups during search.
public struct RecruitContext: Codable, Hashable, Sendable {
    public var input: BattleInput
    public var definitions: [String: Card]
    public var powerCosts: [String: Int]
    public var build: Int?

    public init(input: BattleInput, definitions: [String: Card], powerCosts: [String: Int] = [:], build: Int? = nil) {
        self.input = input
        self.definitions = definitions
        self.powerCosts = powerCosts
        self.build = build
    }

    public func text(_ id: String) -> String {
        Self.plain(definitions[id]?.text ?? "")
    }

    public static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>|\\[x\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func golden(_ id: String) -> Card? {
        guard let dbf = definitions[id]?.battlegroundsPremiumDbfId else { return nil }
        return definitions.values.first { $0.dbfId == dbf }
    }

    public func base(_ id: String) -> String {
        guard let dbf = definitions[id]?.battlegroundsNormalDbfId else { return id }
        return definitions.values.first { $0.dbfId == dbf }?.id ?? id
    }
}

extension BattleInputBuilder {
    public static func recruitContext(
        store: EntityStore, snapshot: BGSnapshot, cards: CardDB?, request: AdvisorRequest
    ) -> RecruitContext? {
        guard let cards, let local = localSide(store: store, snapshot: snapshot) else { return nil }
        // An empty opponent is just storage for the local board, never a prediction or simulation scenario.
        var empty = local
        empty.board = []
        let base = input(player: local, opponent: empty, snapshot: snapshot, validTribes: request.preview.input?.gameState.validTribes.flatMap {
            Set($0.compactMap { HS.Race(rawValue: $0) })
        })
        var definitions: [String: Card] = [:]
        let tokens = ["BG20_GEM", "BG28_810", "BGS_115t", "BGS_115t_G", "BG_CFM_315t", "TB_BaconUps_093t"]
        let ids = (request.board + request.hand + request.shop).map(\.cardID)
            + local.player.heroPowers.map(\.cardId) + tokens
        for id in ids {
            guard let card = cards[id] else { continue }
            definitions[id] = card
            for dbf in [card.battlegroundsNormalDbfId, card.battlegroundsPremiumDbfId].compactMap({ $0 }) {
                if let related = cards.card(dbfID: dbf) { definitions[related.id] = related }
            }
        }
        var costs: [String: Int] = [:]
        for power in local.player.heroPowers {
            if let cost = store[power.entityId]?.int(GameTag.id(48)) { costs[power.cardId] = cost }
        }
        return RecruitContext(input: base, definitions: definitions, powerCosts: costs, build: cards.build)
    }
}

/// Stable entity identities are used inside a plan; UI indices are resolved at each step.
public struct RecruitStep: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case buy, play, sell, spell, power, level, roll, freeze, move }
    public var kind: Kind
    public var entityID: Int
    public var targetID: Int?
    public var position: Int?
    public var action: AdvisorAction
    public var title: String
    public init(kind: Kind, entityID: Int = 0, targetID: Int? = nil, position: Int? = nil,
                action: AdvisorAction, title: String) {
        self.kind = kind; self.entityID = entityID; self.targetID = targetID
        self.position = position; self.action = action; self.title = title
    }
    public var id: String { "\(kind.rawValue):\(entityID):\(targetID ?? 0):\(position ?? -1)" }
}

public struct RecruitState: Hashable, Sendable {
    public var board: [AdvisorCard]
    public var hand: [AdvisorCard]
    public var shop: [AdvisorCard]
    public var gold: Int
    public var tier: Int
    public var levelCost: Int?
    public var rollCost: Int?
    public var frozen: Bool
    public var input: BattleInput
    public var steps: [RecruitStep] = []
    public var limitations: [String] = []
    /// Search never fabricates a shop, discover, or random effect. Replan when the log reveals it.
    public var terminal = false
    public var freeRolls = 0
    public var pendingDiscover = 0
    public var nextEntityID = -1

    public init(request: AdvisorRequest, context: RecruitContext) {
        board = request.board; hand = request.hand; shop = request.shop; gold = request.gold; tier = request.tier
        levelCost = request.levelCost; rollCost = request.rollCost; frozen = request.shopFrozen; input = context.input
    }

    public var combatInput: BattleInput {
        var result = input
        result.playerBoard.board = board.map(\.entity)
        result.playerBoard.player.hand = hand.map(\.entity)
        result.playerBoard.player.tavernTier = tier
        return result
    }
}
