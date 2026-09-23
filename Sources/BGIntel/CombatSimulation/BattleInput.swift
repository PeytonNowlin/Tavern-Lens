// The simulator's input, `BgsBattleInfo` of `@firestone-hs/simulate-bgs-battle`
// (docs/research/simulator-input-mapping.md §2), as Swift values that encode to the JSON it reads.
//
// Field names are the simulator's, so they are camelCase JSON keys (and PascalCase where the
// simulator wants it). Values follow the reference script docs/research/simulator-scripts/build_input.py,
// which reproduced the captured combats: every script-data slot and keyword is sent, zeros and
// false included.
//
// Two fields are Tavern Lens extensions, resolved to card IDs inside the bundle (Tools/Simulator/entry.js)
// because only the simulator's card DB is sure to be loaded: `gameState.anomalyDbfIds` and
// `BoardEntity.additionalCardDbfIds`.

/// `BgsBattleInfo`.
public struct BattleInput: Codable, Hashable, Sendable {
    public var playerBoard: BattleBoard
    public var opponentBoard: BattleBoard
    public var options: BattleOptions
    public var gameState: BattleGameState
}

/// `BgsBoardInfo`: one side of the combat.
public struct BattleBoard: Codable, Hashable, Sendable {
    public var player: BattlePlayer
    /// Left to right.
    public var board: [BattleEntity]
}

/// `BgsPlayerEntity`.
public struct BattlePlayer: Codable, Hashable, Sendable {
    /// The hero's card. For a dead opponent (ghost), the real hero, with `hpLeft <= 0`.
    public var cardId: String
    public var entityId: Int
    /// `HEALTH + ARMOR − DAMAGE`.
    public var hpLeft: Int
    public var tavernTier: Int
    public var heroPowers: [BattleHeroPower]
    public var questEntities: [BattleQuest]
    public var questRewards: [String]
    public var questRewardEntities: [BattleQuestReward]
    public var hand: [BattleEntity]
    /// Secrets, including the Deity sigil.
    public var secrets: [BattleSecret]
    public var trinkets: [BattleTrinket]
    /// Per-game counters by the simulator's key (mapping §6).
    public var globalInfo: [String: Int]
}

/// `BgsHeroPower`.
public struct BattleHeroPower: Codable, Hashable, Sendable {
    public var cardId: String
    public var entityId: Int
    public var used: Bool
    /// `TAG_SCRIPT_DATA_NUM_1`, or a special case's target (mapping §5.3).
    public var info: HeroPowerInfo
    public var info2: Int
    public var info3: Int
    public var info4: Int
    public var info5: Int
    public var info6: Int
    public var scoreValue1: Int
    public var scoreValue2: Int
    public var scoreValue3: Int
    public var locked: Int
}

/// A hero power's `info`: a number (script data or a target entity ID), a created card's ID,
/// or a whole minion (Lock and Load, Rapid Reanimation).
public indirect enum HeroPowerInfo: Codable, Hashable, Sendable {
    case number(Int)
    case cardID(String)
    case entity(BattleEntity)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
            self = .number(number)
        } else if let card = try? container.decode(String.self) {
            self = .cardID(card)
        } else {
            self = .entity(try container.decode(BattleEntity.self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let n): try container.encode(n)
        case .cardID(let id): try container.encode(id)
        case .entity(let entity): try container.encode(entity)
        }
    }
}

/// `BgsQuestEntity` (PascalCase, as the simulator reads it).
public struct BattleQuest: Codable, Hashable, Sendable {
    public var CardId: String
    public var RewardDbfId: Int
    public var ProgressCurrent: Int
    public var ProgressTotal: Int
}

/// A quest reward entity (PascalCase in the input).
public struct BattleQuestReward: Codable, Hashable, Sendable {
    public var CardId: String
    public var ScriptDataNum1: Int
}

/// `BoardEntity`: a minion on the board or a card in hand.
public struct BattleEntity: Codable, Hashable, Sendable {
    public var entityId: Int
    public var cardId: String
    /// Current stats: the log's values already include every buff and aura.
    public var attack: Int
    /// `HEALTH − DAMAGE`.
    public var health: Int
    /// `HEALTH`.
    public var maxHealth: Int
    public var taunt: Bool
    public var divineShield: Bool
    public var poisonous: Bool
    public var venomous: Bool
    public var reborn: Bool
    public var stealth: Bool
    /// `WINDFURY ∈ {1, 3}` or `MEGA_WINDFURY == 1`.
    public var windfury: Bool
    /// `UNPLAYABLE_VISUALS` or `LITERALLY_UNPLAYABLE` (cards in hand).
    public var locked: Bool
    public var enchantments: [BattleEnchantment]
    public var scriptDataNum1: Int
    public var scriptDataNum2: Int
    public var scriptDataNum3: Int
    public var scriptDataNum4: Int
    public var scriptDataNum5: Int
    public var scriptDataNum6: Int
    /// `{4036: BACON_YAMATO_CANNON}` when present; empty otherwise.
    public var tags: [String: Int]
    /// Tavern Lens extension: `MODULAR_ENTITY_PART_1/2` dbfIds, resolved in the bundle to
    /// `additionalCards` (minus the card itself).
    public var additionalCardDbfIds: [Int]?
}

/// `BoardEnchantment`.
public struct BattleEnchantment: Codable, Hashable, Sendable {
    /// The enchantment's card ID, or a dbfId as a string (the simulator resolves those).
    public var cardId: String
    /// The enchantment's own entity ID (a creator's, for the dbfId entries).
    public var originEntityId: Int
    public var tagScriptDataNum1: Int?
    public var tagScriptDataNum2: Int?
    /// Always 0; the simulator assigns it.
    public var timing: Int = 0
}

/// `BoardSecret`, including the Deity sigil.
public struct BattleSecret: Codable, Hashable, Sendable {
    public var entityId: Int
    public var cardId: String
    public var scriptDataNum1: Int
    public var scriptDataNum2: Int
    public var scriptDataNum3: Int
    public var scriptDataNum6: Int
    /// The Deity's stats as tags 4914/4915 (the simulator prefers them over sdn2/sdn3).
    public var tags: [String: Int]?
}

/// `BoardTrinket`.
public struct BattleTrinket: Codable, Hashable, Sendable {
    public var cardId: String
    public var entityId: Int
    /// Sent even when 0: a missing value would make the simulator use the card's default.
    public var scriptDataNum1: Int
    public var scriptDataNum2: Int
    public var scriptDataNum6: Int
}

/// `BgsBattleOptions`. The runner may override the budget fields per request.
public struct BattleOptions: Codable, Hashable, Sendable {
    public var numberOfSimulations: Int = 8000
    /// Milliseconds; a hard stop.
    public var maxAcceptableDuration: Int = 2000
    /// The simulator yields its result every this many simulations.
    public var intermediateResults: Int = 200
    public var skipInfoLogs: Bool = true
    public var includeOutcomeSamples: Bool = false
    /// `BACON_COMBAT_DAMAGE_CAP_ENABLED`; the simulator computes the cap from the turn and players alive.
    public var applyDamageCap: Bool

    public init(applyDamageCap: Bool) {
        self.applyDamageCap = applyDamageCap
    }
}

/// `BgsGameState`.
public struct BattleGameState: Codable, Hashable, Sendable {
    /// The BG turn, `(TURN + 1) / 2`.
    public var currentTurn: Int
    /// Card IDs; the bundle adds those of `anomalyDbfIds`.
    public var anomalies: [String]
    /// Tavern Lens extension: `BACON_GLOBAL_ANOMALY_DBID`, resolved in the bundle.
    public var anomalyDbfIds: [Int]?
    public var numberOfPlayersAlive: Int
    /// The lobby's tribes as `Race` numbers; nil (every tribe) while unknown.
    public var validTribes: [Int]?
}
