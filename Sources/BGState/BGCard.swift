import EntityStore
import PowerParser

/// Which part of a Battlegrounds turn the game is in, from `GameEntity TURN`.
public enum BGPhase: String, Codable, Hashable, Sendable {
    /// Before the first recruit phase (`TURN` absent or 0): heroes are being picked.
    case heroPick
    /// `TURN` odd: shopping with Bob.
    case recruit
    /// `TURN` even: from combat setup until the next recruit phase starts.
    case combat

    init(turn: Int) {
        if turn <= 0 {
            self = .heroPick
        } else {
            self = turn % 2 == 1 ? .recruit : .combat
        }
    }
}

/// A minion keyword the log carries as a boolean tag.
///
/// `CLEAVE` isn't a tag, so it isn't here (log validation, correction 5).
public enum BGKeyword: String, Codable, CaseIterable, Hashable, Sendable {
    case taunt, divineShield, reborn, poisonous, venomous, windfury, megaWindfury, stealth
    case deathrattle, battlecry, avenge, magnetic, rally, frozen

    /// The tag's name in `enums.json`.
    public var tagName: String {
        switch self {
        case .taunt: "TAUNT"
        case .divineShield: "DIVINE_SHIELD"
        case .reborn: "REBORN"
        case .poisonous: "POISONOUS"
        case .venomous: "VENOMOUS"
        case .windfury: "WINDFURY"
        case .megaWindfury: "MEGA_WINDFURY"
        case .stealth: "STEALTH"
        case .deathrattle: "DEATHRATTLE"
        case .battlecry: "BATTLECRY"
        case .avenge: "AVENGE"
        case .magnetic: "MAGNETIC"
        case .rally: "BACON_RALLY"
        case .frozen: "FROZEN"
        }
    }

    /// Resolved through the generated enum table once.
    static let tags: [(BGKeyword, GameTag)] = allCases.map { ($0, GameTag(token: Substring($0.tagName))) }
}

/// How a card on the board, in hand or in the shop plays.
public enum BGCardKind: String, Codable, Hashable, Sendable {
    case minion
    /// A tavern spell: `BATTLEGROUND_SPELL` in the shop, `SPELL` once it's in hand.
    case tavernSpell
    /// Anything else, such as a trinket or a hero.
    case other

    init(cardType: String?) {
        switch cardType {
        case "MINION": self = .minion
        case "SPELL", "BATTLEGROUND_SPELL": self = .tavernSpell
        default: self = .other
        }
    }
}

/// A card in a zone (board, hand or shop) at one moment.
///
/// Entity IDs change every turn (the client re-creates your board at each combat),
/// so identity across snapshots is the card ID and position, never `entityID`.
/// The same type describes opponent boards.
public struct BGCard: Codable, Hashable, Sendable {
    public var cardID: String
    /// Current entity; only valid within this snapshot.
    public var entityID: Int
    /// `ZONE_POSITION`, 1-based.
    public var position: Int
    /// The raw `CARDTYPE` name.
    public var cardType: String?
    public var kind: BGCardKind
    /// `ATK`.
    public var attack: Int
    /// Health left: `HEALTH − DAMAGE`.
    public var health: Int
    /// `HEALTH`, including buffs.
    public var maxHealth: Int
    /// `PREMIUM`.
    public var isGolden: Bool
    /// `TECH_LEVEL`, the card's tavern tier.
    public var tier: Int?
    /// In `BGKeyword.allCases` order.
    public var keywords: [BGKeyword]

    public var isFrozen: Bool { keywords.contains(.frozen) }

    init(_ entity: Entity) {
        cardID = entity.cardID
        entityID = entity.id
        position = entity.int(.zonePosition) ?? 0
        cardType = entity.name(.cardType)
        kind = BGCardKind(cardType: cardType)
        attack = entity.int(.atk) ?? 0
        maxHealth = entity.int(.health) ?? 0
        health = maxHealth - (entity.int(.damage) ?? 0)
        isGolden = (entity.int(.premium) ?? 0) != 0
        tier = entity.int(.techLevel)
        keywords = BGKeyword.tags.compactMap { keyword, tag in (entity.int(tag) ?? 0) != 0 ? keyword : nil }
    }

    /// The cards of `controller` in `zone`, in position order.
    ///
    /// Always filtered by zone: the client makes SETASIDE preview copies of the
    /// opponent's board under the local controller at combat setup.
    static func cards(
        in store: EntityStore, controller: Int, zone: String, where include: (BGCardKind, String?) -> Bool
    ) -> [BGCard] {
        store.entities(controller: controller, zone: zone)
            .compactMap { entity -> BGCard? in
                let type = entity.name(.cardType)
                return include(BGCardKind(cardType: type), type) ? BGCard(entity) : nil
            }
            .sorted { ($0.position, $0.entityID) < ($1.position, $1.entityID) }
    }
}

/// A hero's health and progress. The same shape serves every lobby hero.
public struct BGHeroState: Codable, Hashable, Sendable {
    public var entityID: Int
    public var cardID: String
    /// `HEALTH`.
    public var health: Int
    /// `DAMAGE`.
    public var damage: Int
    /// `ARMOR`.
    public var armor: Int
    /// `PLAYER_TECH_LEVEL`, the tavern tier.
    public var tier: Int?
    /// `PLAYER_TRIPLES`.
    public var triples: Int

    /// Effective health: `HEALTH − DAMAGE + ARMOR`. The hero is dead at 0 or below.
    public var hp: Int { health - damage + armor }

    init(_ entity: Entity) {
        entityID = entity.id
        cardID = entity.cardID
        health = entity.int(.health) ?? 0
        damage = entity.int(.damage) ?? 0
        armor = entity.int(.armor) ?? 0
        tier = entity.int(.playerTechLevel)
        triples = entity.int(.playerTriples) ?? 0
    }
}

/// The local player's gold, from the Player entity.
public struct BGGold: Codable, Hashable, Sendable {
    /// `RESOURCES`: this turn's gold.
    public var resources: Int
    /// `RESOURCES_USED`.
    public var used: Int
    /// `TEMP_RESOURCES`: extra gold for this turn only.
    public var temporary: Int
    /// Tag 3148: the most gold a turn can give (10). Nil until the client sets it on turn 1.
    public var cap: Int?

    /// Gold left to spend: `RESOURCES + TEMP_RESOURCES − RESOURCES_USED`.
    public var available: Int { resources + temporary - used }

    public init(resources: Int, used: Int, temporary: Int, cap: Int?) {
        self.resources = resources
        self.used = used
        self.temporary = temporary
        self.cap = cap
    }

    init(_ player: Entity?) {
        resources = player?.int(.resources) ?? 0
        used = player?.int(.resourcesUsed) ?? 0
        temporary = player?.int(.tempResources) ?? 0
        cap = player?.int(.baconGoldCap)
    }
}

/// Everything about the local player that the log shows.
public struct BGLocalPlayer: Hashable, Sendable {
    public var playerID: Int
    /// Nil until a hero is picked (the placeholder hero doesn't count).
    public var hero: BGHeroState?
    public var gold: BGGold
    /// Tavern tier: the hero's `PLAYER_TECH_LEVEL`, else the Player entity's mirror of it.
    public var tier: Int?
    /// Minions in `PLAY`, left to right.
    public var board: [BGCard]
    /// Cards in `HAND`, left to right. Hero-pick options are left out.
    public var hand: [BGCard]
    /// Hero powers, trinkets, the Deity, quests and counters.
    public var mechanics = BGPlayerMechanics()
}

/// Bob's shop during a recruit phase.
public struct BGShop: Hashable, Sendable {
    /// Minions and tavern spells for sale, left to right.
    public var cards: [BGCard]

    public static let empty = BGShop(cards: [])

    /// Whether the shop is frozen: every card carries `FROZEN`.
    public var isFrozen: Bool { !cards.isEmpty && cards.allSatisfy(\.isFrozen) }
}
