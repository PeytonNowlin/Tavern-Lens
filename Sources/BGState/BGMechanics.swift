import EntityStore
import PowerParser

// Tags the mechanics layer reads. Numbers are from HearthstoneJSON enums.json where the
// tag has a name; the rest come from simulator-input-mapping §5–§6 and may change on a patch.
// All are keyed by number, so it doesn't matter whether the client prints a name or a number.
extension GameTag {
    static let tagScriptDataNum1 = GameTag.id(2)
    static let tagScriptDataNum2 = GameTag.id(3)
    static let attached = GameTag.id(40)
    static let exhausted = GameTag.id(43)
    static let creator = GameTag.id(313)
    static let scoreValue1 = GameTag.id(451)
    static let scoreValue2 = GameTag.id(453)
    static let scoreValue3 = GameTag.id(455)
    static let quest = GameTag.id(462)
    static let questProgress = GameTag.id(534)
    static let questProgressTotal = GameTag.id(535)
    static let questRewardDatabaseID = GameTag.id(1089)
    static let sideQuest = GameTag.id(1192)
    static let baconHeroPowerActivated = GameTag.id(1398)
    static let baconCombatDamageCap = GameTag.id(2089)
    static let baconIsBobQuest = GameTag.id(2732)
    static let tagScriptDataNum3 = GameTag.id(2889)
    static let baconGlobalAnomalyDbID = GameTag.id(2897)
    static let tagScriptDataNum4 = GameTag.id(2919)
    static let tagScriptDataNum5 = GameTag.id(2920)
    static let tagScriptDataNum6 = GameTag.id(2921)
    static let baconCombatDamageCapEnabled = GameTag.id(3403)
    static let lockVisual = GameTag.id(4414)
    static let baconGlobalOldGodDbID = GameTag.id(4902)
    static let baconOldGodAttack = GameTag.id(4914)
    static let baconOldGodHealth = GameTag.id(4915)
    static let baconBloodGemBuffAtkValue = GameTag.id(1844)
    static let baconBloodGemBuffHealthValue = GameTag.id(2827)
    static let tavernSpellAttackIncrease = GameTag.id(3989)
    static let tavernSpellHealthIncrease = GameTag.id(3990)

    /// `TAG_SCRIPT_DATA_NUM_1…6`.
    static let scriptData: [GameTag] = [
        .tagScriptDataNum1, .tagScriptDataNum2, .tagScriptDataNum3,
        .tagScriptDataNum4, .tagScriptDataNum5, .tagScriptDataNum6,
    ]
}

/// A buff to a kind of card, such as blood gems or tavern spells.
public struct BGStatBuff: Codable, Hashable, Sendable {
    public var attack: Int
    public var health: Int

    public init(attack: Int, health: Int) {
        self.attack = attack
        self.health = health
    }

    public var isZero: Bool { attack == 0 && health == 0 }
}

/// `TAG_SCRIPT_DATA_NUM_1…6` of an entity; a missing tag is 0.
public struct BGScriptData: Codable, Hashable, Sendable {
    public var values: [Int]

    public init(_ values: [Int]) {
        self.values = values
    }

    init(_ entity: Entity) {
        values = GameTag.scriptData.map { entity.int($0) ?? 0 }
    }

    /// `TAG_SCRIPT_DATA_NUM_<n>`, 1-based.
    public subscript(n: Int) -> Int { n >= 1 && n <= values.count ? values[n - 1] : 0 }

    public var isZero: Bool { values.allSatisfy { $0 == 0 } }
}

/// A hero power and its state.
public struct BGHeroPower: Codable, Hashable, Sendable {
    public var cardID: String
    /// Only valid within this snapshot.
    public var entityID: Int
    /// Used this turn: `BACON_HERO_POWER_ACTIVATED == 1` or `EXHAUSTED == 1` (mapping §5.3).
    public var isUsed: Bool
    /// `TAG_SCRIPT_DATA_NUM_1…6`: the simulator's `info`, `info2…6`.
    public var scriptData: BGScriptData
    /// `SCORE_VALUE_1…3`; the second is avenge progress.
    public var scoreValues: [Int]
    /// `LOCK_VISUAL` (4414).
    public var locked: Int

    init(_ entity: Entity) {
        cardID = entity.cardID
        entityID = entity.id
        isUsed = entity.int(.baconHeroPowerActivated) == 1 || entity.int(.exhausted) == 1
        scriptData = BGScriptData(entity)
        scoreValues = [GameTag.scoreValue1, .scoreValue2, .scoreValue3].map { entity.int($0) ?? 0 }
        locked = entity.int(.lockVisual) ?? 0
    }
}

/// A picked trinket. The placeholders shown until a trinket is picked are left out.
public struct BGTrinket: Codable, Hashable, Sendable {
    public var cardID: String
    /// Only valid within this snapshot.
    public var entityID: Int
    /// `TAG_SCRIPT_DATA_NUM_6`: 1 for the lesser trinket, 2 for the greater.
    public var slot: Int
    /// `TAG_SCRIPT_DATA_NUM_1…6`: the trinket's current buff values.
    public var scriptData: BGScriptData

    /// Shown in the trinket slots until the trinket is picked (seen at BG turn 4).
    public static let placeholderCardIDs: Set<String> = ["BG30_Trinket_1st", "BG30_Trinket_2nd"]

    init(_ entity: Entity) {
        cardID = entity.cardID
        entityID = entity.id
        slot = entity.int(.tagScriptDataNum6) ?? 0
        scriptData = BGScriptData(entity)
    }
}

/// The Deity (the lobby's Old God) and its stats, from the sigil secret `BG_OldGod`.
public struct BGDeity: Codable, Hashable, Sendable {
    /// The sigil's card ID.
    public var cardID: String
    /// Only valid within this snapshot.
    public var entityID: Int
    /// The Deity's own card, as a dbfId: the sigil's `TAG_SCRIPT_DATA_NUM_6`
    /// (130610 C'Thun, 132532 Y'Shaarj). Nil when 0.
    public var deityDbfID: Int?
    /// The Deity's attack: the owning Player's `BACON_OLD_GOD_ATTACK` (4914), else the sigil's sdn2.
    public var attack: Int
    /// The Deity's health: the owning Player's `BACON_OLD_GOD_HEALTH` (4915), else the sigil's sdn3.
    public var health: Int
    /// The sigil's `TAG_SCRIPT_DATA_NUM_1`: Aberration deaths still needed.
    public var progress: Int
    /// The sigil's `TAG_SCRIPT_DATA_NUM_1…6` as logged.
    public var scriptData: BGScriptData

    public static let sigilCardID = "BG_OldGod"

    init(sigil: Entity, player: Entity?) {
        cardID = sigil.cardID
        entityID = sigil.id
        scriptData = BGScriptData(sigil)
        deityDbfID = scriptData[6] > 0 ? scriptData[6] : nil
        progress = scriptData[1]
        // The simulator reads `tags[4914/4915] ?? sdn2/sdn3 ?? 1`; the Player tags go to 0
        // on the bartender slot between combats, so 0 means "not set" there.
        let playerAttack = player?.int(.baconOldGodAttack) ?? 0
        let playerHealth = player?.int(.baconOldGodHealth) ?? 0
        attack = playerAttack > 0 ? playerAttack : max(scriptData[2], 1)
        health = playerHealth > 0 ? playerHealth : max(scriptData[3], 1)
    }
}

/// A secret other than the Deity sigil, a quest or Bob's quest.
public struct BGSecret: Codable, Hashable, Sendable {
    public var cardID: String
    public var entityID: Int
    public var scriptData: BGScriptData

    init(_ entity: Entity) {
        cardID = entity.cardID
        entityID = entity.id
        scriptData = BGScriptData(entity)
    }
}

/// A quest in progress.
public struct BGQuest: Codable, Hashable, Sendable {
    public var cardID: String
    public var entityID: Int
    /// `QUEST_REWARD_DATABASE_ID`.
    public var rewardDbfID: Int?
    /// `QUEST_PROGRESS` / `QUEST_PROGRESS_TOTAL`.
    public var progress: Int
    public var progressTotal: Int

    init(_ entity: Entity) {
        cardID = entity.cardID
        entityID = entity.id
        rewardDbfID = entity.int(.questRewardDatabaseID).flatMap { $0 > 0 ? $0 : nil }
        progress = entity.int(.questProgress) ?? 0
        progressTotal = entity.int(.questProgressTotal) ?? 0
    }
}

/// A quest reward (`BATTLEGROUND_QUEST_REWARD` in play).
public struct BGQuestReward: Codable, Hashable, Sendable {
    public var cardID: String
    public var entityID: Int
    public var scriptData: BGScriptData

    init(_ entity: Entity) {
        cardID = entity.cardID
        entityID = entity.id
        scriptData = BGScriptData(entity)
    }
}

/// An enchantment on the Player entity: several per-game counters live only in one of
/// these, as its `TAG_SCRIPT_DATA_NUM_1/2` (mapping §6 "ench" rows, e.g. `BG25_011pe`).
public struct BGPlayerEnchantment: Codable, Hashable, Sendable {
    public var cardID: String
    public var scriptData: BGScriptData
}

/// Where a player's counters were read from.
public enum BGCounterSource: String, Codable, Hashable, Sendable {
    /// The owning Player entity (always, for the local player).
    case player
    /// The opponent's `Bacon_TagTransferPlayerE`, attached to the bartender slot each combat.
    case tagTransfer
}

/// One player's Battlegrounds mechanics: hero powers, trinkets, the Deity, quests and the
/// per-player counters, as the simulator needs them.
public struct BGPlayerMechanics: Codable, Hashable, Sendable {
    public var heroPowers: [BGHeroPower] = []
    /// Picked trinkets, by slot (lesser first).
    public var trinkets: [BGTrinket] = []
    public var deity: BGDeity?
    public var secrets: [BGSecret] = []
    public var quests: [BGQuest] = []
    public var questRewards: [BGQuestReward] = []
    /// Per-player counters by numeric tag ID (`counterTags`), whether or not the client
    /// printed a name. Only tags present and non-zero are kept.
    public var counters: [Int: Int] = [:]
    /// Enchantments on the Player entity carrying counters, in entity order.
    public var playerEnchantments: [BGPlayerEnchantment] = []
    /// Blood gem buff: the larger of the `BG26_159pe` enchantment and the Player tags 1844/2827.
    public var bloodGem = BGStatBuff(attack: 0, health: 0)
    /// Tavern spell buff: tags 3989/3990.
    public var tavernSpellBuff = BGStatBuff(attack: 0, health: 0)
    public var counterSource: BGCounterSource = .player

    public init() {}

    /// The per-player counter tags the simulator reads (mapping §6), by number. Most are
    /// printed as bare numbers because the client has no name for them.
    public static let counterTags: [Int] = [
        1780,  // NUM_SPELLS_PLAYED_THIS_GAME
        1844,  // BACON_BLOODGEMBUFFATKVALUE
        2358,  // pirates played this game
        2717,  // friendly minions that died last turn
        2827,  // BACON_BLOODGEMBUFFHEALTHVALUE
        2878,  // elementals played this game
        3088,  // tavern spells played this game
        3236,  // battlecries triggered (HDT)
        3491,  // spells played this turn
        3670,  // magnetized this game
        3685,  // pirates summoned this game
        3873,  // battlecries triggered (Firestone)
        3962,  // beasts summoned this game
        3989,  // TAVERN_SPELL_ATTACK_INCREASE
        3990,  // TAVERN_SPELL_HEALTH_INCREASE
        4001,  // BACON_ELEMENTAL_BUFFHEALTHVALUE
        4002,  // BACON_ELEMENTAL_BUFFATKVALUE
        4212,  // gold spent this game
        4468,  // volumizer attack buff
        4469,  // volumizer health buff
        4639,  // deathrattles triggered this game
        4640,  // (same value as 4639 so far)
        4768,  // cards discarded this game
        4799,  // golden minions played this game
        4803,  // tasty lobster buff
    ]

    /// Counters the game rewrites on the slot Player after the tag transfer, so the Player
    /// entity wins over the transfer for them (mapping §6).
    static let playerFirstTags: Set<Int> = [3989, 3990]

    static let tagTransferCardID = "Bacon_TagTransferPlayerE"
    static let bloodGemEnchantmentCardID = "BG26_159pe"

    /// The mechanics of whoever `playerID` controls in the store now.
    ///
    /// - Parameter useTagTransfer: read counters from the latest `Bacon_TagTransferPlayerE`
    ///   on the Player entity first (the opponent side, during combat).
    static func read(
        _ store: EntityStore, playerID: Int, playerEntityID: Int, useTagTransfer: Bool
    ) -> BGPlayerMechanics {
        var mechanics = BGPlayerMechanics()
        let player = store[playerEntityID]
        let play = store.entities(controller: playerID, zone: "PLAY").sorted { $0.id < $1.id }
        let secretZone = store.entities(controller: playerID, zone: "SECRET").sorted { $0.id < $1.id }

        mechanics.heroPowers = play.filter { $0.name(.cardType) == "HERO_POWER" }.map(BGHeroPower.init)
        mechanics.trinkets = play
            .filter { $0.name(.cardType) == "BATTLEGROUND_TRINKET" && !BGTrinket.placeholderCardIDs.contains($0.cardID) }
            .map(BGTrinket.init)
            .sorted { ($0.slot, $0.entityID) < ($1.slot, $1.entityID) }
        mechanics.questRewards = play
            .filter { $0.name(.cardType) == "BATTLEGROUND_QUEST_REWARD" }
            .map(BGQuestReward.init)

        for entity in secretZone {
            if entity.int(.quest) == 1 {
                if entity.name(.cardType) == "SPELL" { mechanics.quests.append(BGQuest(entity)) }
            } else if entity.int(.sideQuest) == 1 || entity.int(.baconIsBobQuest) == 1 {
                continue
            } else if entity.cardID == BGDeity.sigilCardID {
                // Should there ever be two, the latest is the one in use.
                mechanics.deity = BGDeity(sigil: entity, player: player)
            } else {
                mechanics.secrets.append(BGSecret(entity))
            }
        }

        let enchantments = play.filter {
            $0.name(.cardType) == "ENCHANTMENT" && $0.int(.attached) == playerEntityID && !$0.cardID.isEmpty
        }
        let transfer = useTagTransfer ? enchantments.last { $0.cardID == tagTransferCardID } : nil
        mechanics.counterSource = transfer == nil ? .player : .tagTransfer
        mechanics.playerEnchantments = enchantments
            .filter { $0.cardID != tagTransferCardID }
            .map { BGPlayerEnchantment(cardID: $0.cardID, scriptData: BGScriptData($0)) }

        for number in counterTags {
            let tag = GameTag.id(number)
            let sources = playerFirstTags.contains(number) ? [player, transfer] : [transfer, player]
            guard let value = sources.lazy.compactMap({ $0?.int(tag) }).first, value != 0 else { continue }
            mechanics.counters[number] = value
        }

        let gemEnchantment = mechanics.playerEnchantments.last { $0.cardID == bloodGemEnchantmentCardID }
        mechanics.bloodGem = BGStatBuff(
            attack: max(gemEnchantment?.scriptData[1] ?? 0, mechanics.counters[1844] ?? 0),
            health: max(gemEnchantment?.scriptData[2] ?? 0, mechanics.counters[2827] ?? 0)
        )
        mechanics.tavernSpellBuff = BGStatBuff(
            attack: mechanics.counters[3989] ?? 0, health: mechanics.counters[3990] ?? 0
        )
        return mechanics
    }
}

/// Game-wide Battlegrounds mechanics on the game entity.
public struct BGGameMechanics: Codable, Hashable, Sendable {
    /// `BACON_COMBAT_DAMAGE_CAP` (2089): the most damage a combat can deal to a hero.
    public var damageCap: Int?
    /// `BACON_COMBAT_DAMAGE_CAP_ENABLED` (3403) == 1.
    public var damageCapEnabled: Bool
    /// `BACON_GLOBAL_ANOMALY_DBID` (2897); nil when there's no anomaly.
    public var anomalyDbfID: Int?
    /// `BACON_GLOBAL_OLD_GOD_DBID` (4902): the lobby's Deity; nil when none.
    public var deityDbfID: Int?
    /// Heroes still alive on the leaderboard.
    public var playersAlive: Int

    public init(damageCap: Int?, damageCapEnabled: Bool, anomalyDbfID: Int?, deityDbfID: Int?, playersAlive: Int) {
        self.damageCap = damageCap
        self.damageCapEnabled = damageCapEnabled
        self.anomalyDbfID = anomalyDbfID
        self.deityDbfID = deityDbfID
        self.playersAlive = playersAlive
    }

    init(game: Entity?, lobby: [BGLobbyEntry]) {
        let positive = { (tag: GameTag) -> Int? in game?.int(tag).flatMap { $0 > 0 ? $0 : nil } }
        self.init(
            damageCap: game?.int(.baconCombatDamageCap),
            damageCapEnabled: game?.int(.baconCombatDamageCapEnabled) == 1,
            anomalyDbfID: positive(.baconGlobalAnomalyDbID),
            deityDbfID: positive(.baconGlobalOldGodDbID),
            playersAlive: lobby.filter { !$0.isDead }.count
        )
    }
}

extension BGSnapshot {
    /// The bartender slot's mechanics while it holds the combat opponent; nil otherwise.
    /// Counters come from the opponent's tag-transfer enchantment first.
    static func combatOpponentMechanics(_ store: EntityStore) -> BGPlayerMechanics? {
        guard combatOpponent(store) != nil, let slot = store.otherPlayer else { return nil }
        return BGPlayerMechanics.read(store, playerID: slot.playerID, playerEntityID: slot.entityID, useTagTransfer: true)
    }
}
