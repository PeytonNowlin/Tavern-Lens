import EntityStore
import PowerParser

extension GameTag {
    /// `IS_BACON_POOL_MINION`: the server stamps 1 on the pool minions it sends.
    static let isBaconPoolMinion = GameTag.id(1456)
}

/// One card the log revealed that says something about the lobby's minion pool and tribes.
public struct BGSighting: Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        /// Bob offered it: a new shop minion in a recruit phase (frozen carry-overs aren't new).
        case shop
        /// On the opponent's board at the start of a combat, before the first attack.
        case opponentBoard
        /// Any minion entity the server flagged `IS_BACON_POOL_MINION=1`, once per card.
        case poolFlagged
        /// A hero in the lobby or among the local player's hero-pick options.
        case hero
    }

    public var kind: Kind
    public var cardID: String
    /// The BG turn it was seen in (0 at the hero pick).
    public var bgTurn: Int
    /// The local player's tavern tier when it was seen.
    public var tavernTier: Int?
    /// The card's `TECH_LEVEL` on its entity.
    public var cardTier: Int?
    /// `IS_BACON_POOL_MINION` on its entity, if set.
    public var poolFlag: Int?
    public var position: LogPosition

    public init(
        kind: Kind, cardID: String, bgTurn: Int, tavernTier: Int? = nil, cardTier: Int? = nil, poolFlag: Int? = nil,
        position: LogPosition
    ) {
        self.kind = kind
        self.cardID = cardID
        self.bgTurn = bgTurn
        self.tavernTier = tavernTier
        self.cardTier = cardTier
        self.poolFlag = poolFlag
        self.position = position
    }
}

/// Collects `BGSighting`s from the log, at task-list boundaries, following the validated
/// method of the minion-pool research (§A.7, `tribe_events.py`):
///
/// - **Shop:** the bartender slot's `MINION`s in `PLAY` while `TURN` is odd and the slot's
///   `BACON_CURRENT_COMBAT_PLAYER_ID` is 0. Each entity counts once; a minion frozen at the
///   end of the last recruit phase and still there is a carry-over, not a new draw.
/// - **Opponent board:** the slot's `PLAY` minions while `TURN` is even and the slot is
///   fighting, until the combat's first `ATTACK` block.
/// - **Pool-flagged:** any minion with `IS_BACON_POOL_MINION=1`, once per card, for the
///   pool's self-heal.
/// - **Heroes:** lobby heroes and the local hero-pick options, through BG turn 1.
///
/// One collector per game: the owner makes a new one when a different game starts, and
/// keeps it across a reconnect of the same game (resent entities keep their IDs).
public struct BGSightingCollector: Sendable {
    private var turn = 0
    private var shopSeen: Set<Int> = []
    private var opponentSeen: Set<Int> = []
    private var lastShop: [(cardID: String, frozen: Bool)] = []
    private var previousFrozen: [String] = []
    private var carryOver: [String] = []
    private var attackSeen = false
    /// Entities flagged as pool minions whose card isn't reported yet (it may still be hidden).
    private var pendingFlagged: Set<Int> = []
    private var flaggedCards: Set<String> = []
    private var heroesSeen: Set<String> = []

    public init() {}

    /// Feed every change, with the store as it is after the change.
    public mutating func observe(_ change: EntityChange, in store: EntityStore) {
        switch change {
        case .entityCreated(let id):
            if store[id]?.int(.isBaconPoolMinion) == 1 { pendingFlagged.insert(id) }
        case .tagChanged(let id, .isBaconPoolMinion, _, .int(1)):
            pendingFlagged.insert(id)
        default:
            break
        }
    }

    /// Feed every event (for the combat's first attack).
    public mutating func observe(_ event: PowerEvent) {
        if case .blockStart(type: "ATTACK", _) = event { attackSeen = true }
    }

    /// At `PowerProcessor.EndCurrentTaskList`: the sightings this batch revealed.
    public mutating func taskListEnded(_ store: EntityStore, at position: LogPosition) -> [BGSighting] {
        guard let game = store.gameEntity else { return [] }
        var sightings: [BGSighting] = []
        let currentTurn = game.int(.turn) ?? 0
        if currentTurn != turn {
            if currentTurn % 2 == 0 {
                // A recruit phase ended: what was frozen in it may still be there next turn.
                previousFrozen = lastShop.filter(\.frozen).map(\.cardID)
            } else {
                carryOver = previousFrozen
            }
            attackSeen = false
            turn = currentTurn
        }
        let bgTurn = (currentTurn + 1) / 2
        let tavernTier = BGSnapshot.localPlayer(store)?.tier

        if let slot = store.otherPlayer {
            let combatPlayer = store[slot.entityID]?.int(.baconCurrentCombatPlayerID) ?? 0
            let minions = store.entities(controller: slot.playerID, zone: "PLAY")
                .filter { $0.name(.cardType) == "MINION" }
                .sorted { $0.id < $1.id }
            if currentTurn > 0, currentTurn % 2 == 1, combatPlayer == 0 {
                lastShop = minions.map { ($0.cardID, ($0.int(.frozen) ?? 0) != 0) }
                for entity in minions where shopSeen.insert(entity.id).inserted {
                    if let index = carryOver.firstIndex(of: entity.cardID) {
                        carryOver.remove(at: index)
                        continue
                    }
                    sightings.append(sighting(.shop, entity, bgTurn, tavernTier, position))
                }
            } else if currentTurn > 0, currentTurn % 2 == 0, combatPlayer != 0, !attackSeen {
                for entity in minions where opponentSeen.insert(entity.id).inserted {
                    sightings.append(sighting(.opponentBoard, entity, currentTurn / 2, tavernTier, position))
                }
            }
        }

        for id in pendingFlagged {
            guard let entity = store[id], !entity.cardID.isEmpty else { continue }
            pendingFlagged.remove(id)
            guard entity.name(.cardType) == "MINION", flaggedCards.insert(entity.cardID).inserted else { continue }
            sightings.append(sighting(.poolFlagged, entity, bgTurn, tavernTier, position))
        }

        if bgTurn <= 1 {
            var heroes: [String] = []
            if let local = store.localPlayer {
                heroes += store.entities(controller: local.playerID, zone: "HAND")
                    .filter { $0.name(.cardType) == "HERO" }
                    .sorted { $0.id < $1.id }
                    .map(\.cardID)
            }
            heroes += BGSnapshot.lobby(store, local: BGSnapshot.localPlayer(store)).map(\.hero.cardID)
            for hero in heroes where !hero.isEmpty && hero != BGSnapshot.placeholderHeroCardID
                && heroesSeen.insert(hero).inserted {
                sightings.append(BGSighting(kind: .hero, cardID: hero, bgTurn: bgTurn, position: position))
            }
        }
        return sightings
    }

    private func sighting(
        _ kind: BGSighting.Kind, _ entity: Entity, _ bgTurn: Int, _ tavernTier: Int?, _ position: LogPosition
    ) -> BGSighting {
        BGSighting(
            kind: kind, cardID: entity.cardID, bgTurn: bgTurn, tavernTier: tavernTier,
            cardTier: entity.int(.techLevel), poolFlag: entity.int(.isBaconPoolMinion), position: position
        )
    }
}
