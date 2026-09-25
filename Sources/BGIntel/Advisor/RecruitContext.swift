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
    public var darkDiscovery: DarkDiscovery?
    /// No recruit actions are available until an outstanding discover/choice resolves.
    public var pendingChoice: Bool?
    /// Hand minions linked by observed discard enchantment source and batch.
    public var linkedDiscards: [Int: [Int]]?
    public struct DarkDiscovery: Codable, Hashable, Sendable {
        public var entityID: Int
        public var cost: Int
        public var remainingUses: Int
        public var minTier: Int
        public var maxTier: Int
        public var ready: Bool
    }
    /// Observed interaction state. Absent in older archives: never assume an activation is ready.
    public var activations: [Int: Activation]?
    public struct Activation: Codable, Hashable, Sendable {
        public var ready: Bool
        public var cost: Int
        public init(ready: Bool, cost: Int) { self.ready = ready; self.cost = cost }
    }

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
        let tokens = ["BG20_GEM", "BG28_810", "BGS_115t", "BGS_115t_G", "BG_CFM_315t", "TB_BaconUps_093t", "BG36_301t"]
        let observed = request.board + request.hand + request.shop
        var ids = observed.map(\.cardID)
        ids += local.player.heroPowers.map(\.cardId)
        ids += local.player.trinkets.map(\.cardId)
        ids += local.player.secrets.map(\.cardId)
        ids += observed.flatMap { $0.entity.enchantments.map(\.cardId) }
        ids += tokens
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
        var context = RecruitContext(input: base, definitions: definitions, powerCosts: costs, build: cards.build)
        // The combat enchantment schema keeps only script data 1/2. Recruit pairing also
        // needs 3 (batch), so read it from the live store instead of guessing from card IDs.
        var discardGroups: [String: [Int]] = [:]
        for card in request.hand {
            for enchantment in card.entity.enchantments where enchantment.cardId == "BG36_308e" {
                guard let entity = store[enchantment.originEntityId],
                      let source = entity.int(GameTag.id(3)), source > 0,
                      let batch = entity.int(GameTag.id(2889)),
                      entity.int(GameTag.id(2)) == 1 else { continue }
                discardGroups["\(source):\(batch)", default: []].append(card.entity.entityId)
            }
        }
        context.linkedDiscards = [:]
        for ids in discardGroups.values {
            for id in ids { context.linkedDiscards?[id] = ids.filter { $0 != id } }
        }
        context.activations = [:]
        for card in request.board + request.hand + request.shop where context.text(card.cardID).contains("Activate (") {
            guard let entity = store[card.entity.entityId] else { continue }
            let parsed = RecruitEffects.captures(".*Activate \\(([0-9]+)\\):.*", context.text(card.cardID))
            context.activations?[card.entity.entityId] = .init(
                ready: entity.int(GameTag.id(4089)) == 1,
                cost: entity.int(GameTag.id(4090)) ?? parsed.flatMap { Int($0[0]) } ?? 0)
        }
        if let player = store.localPlayer,
           let button = store.entities(controller: player.playerID, zone: "PLAY")
            .filter({ $0.cardID == "BG36_Button_DarkGift" && $0.name(.cardType) == "GAME_MODE_BUTTON" })
            .max(by: { $0.id < $1.id }),
           let cost = button.int(GameTag.id(48)), cost >= 0,
           let uses = button.int(GameTag.id(3)),
           let low = button.int(GameTag.id(2889)), let high = button.int(GameTag.id(2919)),
           (1...6).contains(low), (low...6).contains(high) {
            context.darkDiscovery = .init(entityID: button.id, cost: cost, remainingUses: max(0, uses),
                minTier: low, maxTier: high, ready: snapshot.bgTurn >= 3 && uses > 0
                    && button.int(GameTag.id(4414)) == 0
                    && button.int(GameTag.id(43)) != 1 && button.int(GameTag.id(225)) != 1)
            if let definition = cards[button.cardID] { context.definitions[button.cardID] = definition }
        }
        return context
    }
}

/// Stable entity identities are used inside a plan; UI indices are resolved at each step.
public struct RecruitStep: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case buy, play, sell, spell, power, activate, darkDiscovery, level, roll, freeze, move }
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
    public var usedActivations: Set<Int> = []
    /// Random rewards have option value but cannot be played before the log reveals them.
    public var unknownRewards = 0

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
