import BGState
import HSData

/// Game-wide mechanics: the damage cap, anomaly and Deity of the lobby.
public struct GameMechanicsView: Codable, Hashable, Sendable {
    /// The most damage a combat can deal to a hero; nil until the game sets it.
    public var damageCap: Int?
    public var damageCapEnabled: Bool
    /// The anomaly's card ID, from its dbfId via the card data; nil without either.
    public var anomalyCardID: String?
    public var anomalyDbfID: Int?
    /// The lobby's Deity (C'Thun, Y'Shaarj …) as a dbfId, and its card ID with card data.
    public var deityDbfID: Int?
    public var deityCardID: String?
    /// Heroes still alive.
    public var playersAlive: Int

    public init(
        damageCap: Int?, damageCapEnabled: Bool, anomalyCardID: String? = nil, anomalyDbfID: Int? = nil,
        deityDbfID: Int? = nil, deityCardID: String? = nil, playersAlive: Int
    ) {
        self.damageCap = damageCap
        self.damageCapEnabled = damageCapEnabled
        self.anomalyCardID = anomalyCardID
        self.anomalyDbfID = anomalyDbfID
        self.deityDbfID = deityDbfID
        self.deityCardID = deityCardID
        self.playersAlive = playersAlive
    }
}

/// One player's Battlegrounds mechanics.
///
/// Compact JSON: empty lists, zero buffs and the default counter source are left out.
public struct MechanicsView: Codable, Hashable, Sendable {
    public var heroPowers: [HeroPowerView]
    /// Picked trinkets, lesser first; the placeholders are left out.
    public var trinkets: [TrinketView]
    public var deity: DeityView?
    /// Card IDs of secrets other than the Deity sigil.
    public var secrets: [String]
    public var quests: [QuestView]
    /// Card IDs of quest rewards.
    public var questRewards: [String]
    /// Per-player counters by numeric tag ID, named or not (e.g. 3088 tavern spells played,
    /// 4212 gold spent). Only non-zero values.
    public var counters: [Int: Int]
    /// Nil when zero.
    public var bloodGem: StatBuffView?
    /// Nil when zero.
    public var tavernSpellBuff: StatBuffView?
    /// The counters came from the opponent's tag-transfer enchantment rather than the Player entity.
    public var countersFromTagTransfer: Bool

    public init(
        heroPowers: [HeroPowerView] = [], trinkets: [TrinketView] = [], deity: DeityView? = nil,
        secrets: [String] = [], quests: [QuestView] = [], questRewards: [String] = [], counters: [Int: Int] = [:],
        bloodGem: StatBuffView? = nil, tavernSpellBuff: StatBuffView? = nil, countersFromTagTransfer: Bool = false
    ) {
        self.heroPowers = heroPowers
        self.trinkets = trinkets
        self.deity = deity
        self.secrets = secrets
        self.quests = quests
        self.questRewards = questRewards
        self.counters = counters
        self.bloodGem = bloodGem
        self.tavernSpellBuff = tavernSpellBuff
        self.countersFromTagTransfer = countersFromTagTransfer
    }

    private enum CodingKeys: String, CodingKey {
        case heroPowers, trinkets, deity, secrets, quests, questRewards, counters, bloodGem, tavernSpellBuff
        case countersFromTagTransfer
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        heroPowers = try c.decodeIfPresent([HeroPowerView].self, forKey: .heroPowers) ?? []
        trinkets = try c.decodeIfPresent([TrinketView].self, forKey: .trinkets) ?? []
        deity = try c.decodeIfPresent(DeityView.self, forKey: .deity)
        secrets = try c.decodeIfPresent([String].self, forKey: .secrets) ?? []
        quests = try c.decodeIfPresent([QuestView].self, forKey: .quests) ?? []
        questRewards = try c.decodeIfPresent([String].self, forKey: .questRewards) ?? []
        counters = try c.decodeIfPresent([Int: Int].self, forKey: .counters) ?? [:]
        bloodGem = try c.decodeIfPresent(StatBuffView.self, forKey: .bloodGem)
        tavernSpellBuff = try c.decodeIfPresent(StatBuffView.self, forKey: .tavernSpellBuff)
        countersFromTagTransfer = try c.decodeIfPresent(Bool.self, forKey: .countersFromTagTransfer) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !heroPowers.isEmpty { try c.encode(heroPowers, forKey: .heroPowers) }
        if !trinkets.isEmpty { try c.encode(trinkets, forKey: .trinkets) }
        try c.encodeIfPresent(deity, forKey: .deity)
        if !secrets.isEmpty { try c.encode(secrets, forKey: .secrets) }
        if !quests.isEmpty { try c.encode(quests, forKey: .quests) }
        if !questRewards.isEmpty { try c.encode(questRewards, forKey: .questRewards) }
        if !counters.isEmpty { try c.encode(counters, forKey: .counters) }
        try c.encodeIfPresent(bloodGem, forKey: .bloodGem)
        try c.encodeIfPresent(tavernSpellBuff, forKey: .tavernSpellBuff)
        if countersFromTagTransfer { try c.encode(countersFromTagTransfer, forKey: .countersFromTagTransfer) }
    }
}

public struct HeroPowerView: Codable, Hashable, Sendable {
    public var cardID: String
    public var name: String?
    public var used: Bool
    /// `TAG_SCRIPT_DATA_NUM_1…6`; nil when all zero.
    public var scriptData: [Int]?

    public init(cardID: String, name: String? = nil, used: Bool, scriptData: [Int]? = nil) {
        self.cardID = cardID
        self.name = name
        self.used = used
        self.scriptData = scriptData
    }
}

public struct TrinketView: Codable, Hashable, Sendable {
    public var cardID: String
    public var name: String?
    /// 1 lesser, 2 greater.
    public var slot: Int
    /// `TAG_SCRIPT_DATA_NUM_1…6`, the trinket's buff values; nil when all zero.
    public var scriptData: [Int]?

    public init(cardID: String, name: String? = nil, slot: Int, scriptData: [Int]? = nil) {
        self.cardID = cardID
        self.name = name
        self.slot = slot
        self.scriptData = scriptData
    }
}

/// The Deity's current stats.
public struct DeityView: Codable, Hashable, Sendable {
    /// The Deity's card (e.g. `BGFYM_000` C'Thun) with card data; nil without it.
    public var cardID: String?
    public var name: String?
    public var dbfID: Int?
    public var attack: Int
    public var health: Int
    /// Aberration deaths still needed (the sigil's first script value).
    public var progress: Int

    public init(cardID: String? = nil, name: String? = nil, dbfID: Int?, attack: Int, health: Int, progress: Int) {
        self.cardID = cardID
        self.name = name
        self.dbfID = dbfID
        self.attack = attack
        self.health = health
        self.progress = progress
    }
}

public struct QuestView: Codable, Hashable, Sendable {
    public var cardID: String
    public var name: String?
    public var progress: Int
    public var progressTotal: Int
    public var rewardDbfID: Int?

    public init(cardID: String, name: String? = nil, progress: Int, progressTotal: Int, rewardDbfID: Int? = nil) {
        self.cardID = cardID
        self.name = name
        self.progress = progress
        self.progressTotal = progressTotal
        self.rewardDbfID = rewardDbfID
    }
}

public struct StatBuffView: Codable, Hashable, Sendable {
    public var attack: Int
    public var health: Int

    public init(attack: Int, health: Int) {
        self.attack = attack
        self.health = health
    }
}

// MARK: - From the snapshot

extension GameMechanicsView {
    init(_ mechanics: BGGameMechanics, cards: CardDB?) {
        self.init(
            damageCap: mechanics.damageCap,
            damageCapEnabled: mechanics.damageCapEnabled,
            anomalyCardID: mechanics.anomalyDbfID.flatMap { cards?.card(dbfID: $0)?.id },
            anomalyDbfID: mechanics.anomalyDbfID,
            deityDbfID: mechanics.deityDbfID,
            deityCardID: mechanics.deityDbfID.flatMap { cards?.card(dbfID: $0)?.id },
            playersAlive: mechanics.playersAlive
        )
    }
}

extension MechanicsView {
    init(_ mechanics: BGPlayerMechanics, cards: CardDB?) {
        let name = { (cardID: String) in cardID.isEmpty ? nil : cards?.name(of: cardID) }
        let nonZero = { (data: BGScriptData) in data.isZero ? nil : data.values }
        let buff = { (buff: BGStatBuff) in buff.isZero ? nil : StatBuffView(attack: buff.attack, health: buff.health) }
        self.init(
            heroPowers: mechanics.heroPowers.map {
                HeroPowerView(cardID: $0.cardID, name: name($0.cardID), used: $0.isUsed, scriptData: nonZero($0.scriptData))
            },
            trinkets: mechanics.trinkets.map {
                TrinketView(cardID: $0.cardID, name: name($0.cardID), slot: $0.slot, scriptData: nonZero($0.scriptData))
            },
            deity: mechanics.deity.map { deity in
                let card = deity.deityDbfID.flatMap { cards?.card(dbfID: $0) }
                return DeityView(
                    cardID: card?.id, name: card?.name, dbfID: deity.deityDbfID,
                    attack: deity.attack, health: deity.health, progress: deity.progress
                )
            },
            secrets: mechanics.secrets.map(\.cardID),
            quests: mechanics.quests.map {
                QuestView(
                    cardID: $0.cardID, name: name($0.cardID), progress: $0.progress,
                    progressTotal: $0.progressTotal, rewardDbfID: $0.rewardDbfID
                )
            },
            questRewards: mechanics.questRewards.map(\.cardID),
            counters: mechanics.counters,
            bloodGem: buff(mechanics.bloodGem),
            tavernSpellBuff: buff(mechanics.tavernSpellBuff),
            countersFromTagTransfer: mechanics.counterSource == .tagTransfer
        )
    }
}
