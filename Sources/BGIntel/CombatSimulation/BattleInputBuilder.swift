import BGState
import EntityStore
import HSData
import PowerParser

/// Builds the simulator's input from the entity store at the combat-start moment
/// (the tag 2022 1→0 edge), following docs/research/simulator-input-mapping.md §4–§6.
///
/// The per-player mechanics (hero powers, trinkets, Deity, quests, counters, with the
/// opponent's counters from the tag transfer) come from the snapshot, so they follow the
/// same rules the overlay shows. What only the simulator needs is read from the store here:
/// minions with their enchantments, hands, the hero power special cases and Choral Mrrrglr.
public enum BattleInputBuilder {
    /// Nil when either side is missing: no combat opponent, or no hero.
    ///
    /// - Parameter validTribes: the lobby's tribes; nil sends none (every tribe).
    public static func build(store: EntityStore, snapshot: BGSnapshot, validTribes: Set<HS.Race>?) -> BattleInput? {
        guard let local = store.localPlayer, let slot = store.otherPlayer,
              let localMechanics = snapshot.local?.mechanics,
              let opponentMechanics = snapshot.combatOpponentMechanics
        else { return nil }
        let index = AttachmentIndex(store)
        guard let player = side(store, index, slot: local, mechanics: localMechanics, isOpponent: false),
              let opponent = side(store, index, slot: slot, mechanics: opponentMechanics, isOpponent: true)
        else { return nil }
        let game = snapshot.mechanics
        return BattleInput(
            playerBoard: player,
            opponentBoard: opponent,
            options: BattleOptions(applyDamageCap: game.damageCapEnabled),
            gameState: BattleGameState(
                currentTurn: snapshot.bgTurn,
                anomalies: [],
                anomalyDbfIds: game.anomalyDbfID.map { [$0] },
                numberOfPlayersAlive: game.playersAlive,
                validTribes: validTribes.map { $0.map(\.rawValue).sorted() }
            )
        )
    }

    // MARK: - One side

    private static func side(
        _ store: EntityStore, _ index: AttachmentIndex, slot: PlayerSlot, mechanics: BGPlayerMechanics, isOpponent: Bool
    ) -> BattleBoard? {
        let playerEntity = store[slot.entityID]
        guard let hero = hero(store, slot: slot) else { return nil }
        let controller = slot.playerID

        let boardTypes: Set<String> = ["MINION", "LOCATION", "BATTLEGROUND_SPELL"]
        let boardEntities = inZone(store, controller: controller, zone: "PLAY").filter { entity in
            guard let type = entity.name(.cardType), boardTypes.contains(type) else { return false }
            // The opponent's combat copies are new; older ones are ghost or reconnect leftovers (mapping §4).
            return !isOpponent || (entity.int(T.numTurnsInPlay) ?? 0) <= 1
        }
        let handEntities = inZone(store, controller: controller, zone: "HAND")

        var globalInfo = Self.globalInfo(mechanics)
        if let choral = choralBuff(store, index, board: boardEntities) {
            globalInfo["ChoralAttackBuff"] = choral.attack
            globalInfo["ChoralHealthBuff"] = choral.health
        }

        var secrets = mechanics.secrets.map {
            BattleSecret(
                entityId: $0.entityID, cardId: $0.cardID, scriptDataNum1: $0.scriptData[1],
                scriptDataNum2: $0.scriptData[2], scriptDataNum3: $0.scriptData[3], scriptDataNum6: $0.scriptData[6]
            )
        }
        if let deity = mechanics.deity {
            // The simulator reads `tags[4914/4915] ?? sdn2/sdn3`: without them the Deity is a 1/1 (mapping §5.6).
            secrets.append(BattleSecret(
                entityId: deity.entityID, cardId: deity.cardID, scriptDataNum1: deity.scriptData[1],
                scriptDataNum2: deity.scriptData[2], scriptDataNum3: deity.scriptData[3],
                scriptDataNum6: deity.scriptData[6], tags: ["4914": deity.attack, "4915": deity.health]
            ))
        }
        secrets.sort { $0.entityId < $1.entityId }

        let heroTier = hero.entity.int(.playerTechLevel).flatMap { $0 > 0 ? $0 : nil }
        let player = BattlePlayer(
            cardId: hero.cardID,
            entityId: hero.entity.id,
            hpLeft: hero.hp,
            tavernTier: heroTier ?? playerEntity?.int(.playerTechLevel).flatMap { $0 > 0 ? $0 : nil } ?? 1,
            heroPowers: mechanics.heroPowers.map { heroPower($0, store, index) },
            questEntities: mechanics.quests.map {
                BattleQuest(CardId: $0.cardID, RewardDbfId: $0.rewardDbfID ?? 0,
                            ProgressCurrent: $0.progress, ProgressTotal: $0.progressTotal)
            },
            questRewards: mechanics.questRewards.map(\.cardID),
            questRewardEntities: mechanics.questRewards.map {
                BattleQuestReward(CardId: $0.cardID, ScriptDataNum1: $0.scriptData[1])
            },
            hand: handEntities.map { entity(store, index, $0) },
            secrets: secrets,
            trinkets: mechanics.trinkets.map {
                BattleTrinket(cardId: $0.cardID, entityId: $0.entityID, scriptDataNum1: $0.scriptData[1],
                              scriptDataNum2: $0.scriptData[2], scriptDataNum6: $0.scriptData[6])
            },
            globalInfo: globalInfo
        )
        return BattleBoard(player: player, board: boardEntities.map { entity(store, index, $0) })
    }

    /// A side's entities in a zone, in `ZONE_POSITION` order.
    private static func inZone(_ store: EntityStore, controller: Int, zone: String) -> [Entity] {
        store.entities(controller: controller, zone: zone)
            .sorted { ($0.int(.zonePosition) ?? 0, $0.id) < ($1.int(.zonePosition) ?? 0, $1.id) }
    }

    // MARK: - Hero

    private struct Hero {
        var entity: Entity
        var cardID: String
        var hp: Int
    }

    static let ghostHeroCardIDs: Set<String> = ["TB_BaconShop_HERO_KelThuzad", "TB_BaconShop_HERO_KelThuzad_Deathwhisper"]
    static let placeholderHeroCardID = "TB_BaconShop_HERO_PH"

    private static func isRealHero(_ entity: Entity) -> Bool {
        entity.name(.cardType) == "HERO" && !entity.cardID.isEmpty && entity.cardID != placeholderHeroCardID
            && !entity.cardID.hasPrefix("TB_BaconShopBob") && !ghostHeroCardIDs.contains(entity.cardID)
    }

    /// The Player's `HERO_ENTITY`, else the newest hero it controls in `PLAY` (not Bob, not the
    /// placeholder). A ghost (a dead opponent) is sent as its real hero: the newest real hero
    /// with the same `PLAYER_ID`, with its health at or below 0, and the simulator swaps in the ghost.
    private static func hero(_ store: EntityStore, slot: PlayerSlot) -> Hero? {
        var entity = store[slot.entityID]?.int(.heroEntity).flatMap { store[$0] }
        if entity == nil || entity?.cardID.isEmpty == true {
            entity = store.entities(controller: slot.playerID, zone: "PLAY").filter(isRealHero).max { $0.id < $1.id }
        }
        guard let entity else { return nil }
        let hp = (entity.int(.health) ?? 0) + (entity.int(.armor) ?? 0) - (entity.int(.damage) ?? 0)
        guard ghostHeroCardIDs.contains(entity.cardID) else { return Hero(entity: entity, cardID: entity.cardID, hp: hp) }
        let playerID = entity.int(.playerID)
        let real = store.entities.values
            .filter { isRealHero($0) && playerID != nil && $0.int(.playerID) == playerID }
            .max { $0.id < $1.id }
        guard let real else { return Hero(entity: entity, cardID: entity.cardID, hp: hp) }
        let realHP = (real.int(.health) ?? 0) + (real.int(.armor) ?? 0) - (real.int(.damage) ?? 0)
        return Hero(entity: entity, cardID: real.cardID, hp: min(realHP, 0))
    }

    // MARK: - Minions and cards in hand

    private static func entity(_ store: EntityStore, _ index: AttachmentIndex, _ e: Entity) -> BattleEntity {
        let maxHealth = e.int(.health) ?? 0
        let windfury = e.int(T.windfury) ?? 0
        let is1 = { (tag: GameTag) in e.int(tag) == 1 }
        let sdn = GameTag.scriptDataTags.map { e.int($0) ?? 0 }
        var entity = BattleEntity(
            entityId: e.id,
            cardId: e.cardID,
            attack: e.int(.atk) ?? 0,
            health: maxHealth - (e.int(.damage) ?? 0),
            maxHealth: maxHealth,
            taunt: is1(T.taunt),
            divineShield: is1(T.divineShield),
            poisonous: is1(T.poisonous),
            venomous: is1(T.venomous),
            reborn: is1(T.reborn),
            stealth: is1(T.stealth),
            windfury: windfury == 1 || windfury == 3 || is1(T.megaWindfury),
            locked: is1(T.unplayableVisuals) || is1(T.literallyUnplayable),
            enchantments: enchantments(store, index, of: e),
            scriptDataNum1: sdn[0], scriptDataNum2: sdn[1], scriptDataNum3: sdn[2],
            scriptDataNum4: sdn[3], scriptDataNum5: sdn[4], scriptDataNum6: sdn[5],
            tags: e.int(T.yamatoCannon).map { ["4036": $0] } ?? [:]
        )
        let parts = [T.modularPart1, T.modularPart2].compactMap { e.int($0) }.filter { $0 > 0 }
        if !parts.isEmpty { entity.additionalCardDbfIds = parts }
        // Lovesick Balladist: its buff is the latest Serenaded enchantment it created, halved when golden (mapping §5.4).
        if e.cardID.hasPrefix(SpecialCard.lovesickBalladist) {
            let serenade = index.all
                .filter { $0.cardID == SpecialCard.serenadedEnchantment && $0.int(.creator) == e.id }
                .max { $0.id < $1.id }
            if let value = serenade?.int(.tagScriptDataNum1) {
                entity.scriptDataNum1 = e.int(.premium) == 1 ? value / 2 : value
            }
        }
        return entity
    }

    /// Enchantments attached to `e` (not removed), plus for each magnetic one the magnetic
    /// enchantments of its creator, recursively (mapping §4), plus the dbfId entries of
    /// Polarizing Beatboxer and Clunker Junker (§5.5).
    private static func enchantments(_ store: EntityStore, _ index: AttachmentIndex, of e: Entity) -> [BattleEnchantment] {
        var result: [BattleEnchantment] = []
        var seen: Set<Int> = []
        func add(_ enchantment: Entity) {
            guard seen.insert(enchantment.id).inserted else { return }
            result.append(BattleEnchantment(
                cardId: enchantment.cardID, originEntityId: enchantment.id,
                tagScriptDataNum1: enchantment.int(.tagScriptDataNum1) ?? 0,
                tagScriptDataNum2: enchantment.int(.tagScriptDataNum2) ?? 0
            ))
            if enchantment.int(T.magnetic) == 1, let creator = enchantment.int(.creator) {
                for inherited in index.attached(to: creator) where inherited.int(T.magnetic) == 1 { add(inherited) }
            }
        }
        for enchantment in index.attached(to: e.id) { add(enchantment) }
        for enchantment in index.attached(to: e.id) where SpecialCard.dbfIDEnchantments.contains(enchantment.cardID) {
            let creator = enchantment.int(.creator)
            let dbfID = creator.flatMap { store[$0]?.int(T.entityAsEnchantment) } ?? enchantment.int(T.creatorDbID)
            if let dbfID, dbfID > 0 {
                result.append(BattleEnchantment(cardId: String(dbfID), originEntityId: creator ?? enchantment.id))
            }
        }
        return result
    }

    // MARK: - Hero powers

    /// `info` is `TAG_SCRIPT_DATA_NUM_1` except for the hero powers that aim at something (mapping §5.3).
    private static func heroPower(_ power: BGHeroPower, _ store: EntityStore, _ index: AttachmentIndex) -> BattleHeroPower {
        var info = HeroPowerInfo.number(power.scriptData[1])
        let created = {
            store.entities.values
                .filter { $0.name(.cardType) == "MINION" && $0.int(.creator) == power.entityID }
                .max { $0.id < $1.id }
        }
        switch power.cardID {
        case SpecialCard.rebornRites where power.isUsed && power.scriptData[1] <= 0:
            if let target = store[power.entityID]?.int(T.cardTarget), target > 0 { info = .number(target) }
        case SpecialCard.embraceYourRage where power.isUsed:
            if let minion = created() { info = .cardID(minion.cardID) }
        case SpecialCard.lockAndLoad where power.isUsed:
            if let minion = created() { info = .entity(entity(store, index, minion)) }
        case let id where SpecialCard.markedMinionHeroPowers[id] != nil:
            let mark = SpecialCard.markedMinionHeroPowers[id]!
            if let marked = index.all.first(where: { $0.cardID == mark })?.int(.attached),
               let minion = store[marked], minion.name(.cardType) == "MINION" {
                info = .entity(entity(store, index, minion))
            }
        default:
            break
        }
        return BattleHeroPower(
            cardId: power.cardID, entityId: power.entityID, used: power.isUsed, info: info,
            info2: power.scriptData[2], info3: power.scriptData[3], info4: power.scriptData[4],
            info5: power.scriptData[5], info6: power.scriptData[6],
            scoreValue1: power.scoreValues[0], scoreValue2: power.scoreValues[1], scoreValue3: power.scoreValues[2],
            locked: power.locked
        )
    }

    // MARK: - Counters

    /// The simulator's `globalInfo` from the per-player counters and Player enchantments (mapping §6).
    /// Every key is sent, zeros included; the simulator treats a missing key as 0 anyway.
    static func globalInfo(_ m: BGPlayerMechanics) -> [String: Int] {
        func ench(_ cardID: String, _ n: Int) -> Int {
            m.playerEnchantments.last { $0.cardID == cardID }?.scriptData[n] ?? 0
        }
        func tag(_ number: Int) -> Int { m.counters[number] ?? 0 }
        return [
            "EternalKnightsDeadThisGame": ench("BG25_008pe", 1),
            "UndeadAttackBonus": ench("BG25_011pe", 1),
            "UndeadHealthBonus": ench("BG25_011pe", 2),
            "HauntedCarapaceAttackBonus": ench("BG33_112pe", 1),
            "HauntedCarapaceHealthBonus": ench("BG33_112pe", 2),
            "GoldrinnBuffAtk": ench("BGS_018pe", 1) + ench("BG34_Giant_362pe", 1),
            "GoldrinnBuffHealth": ench("BGS_018pe", 2) + ench("BG34_Giant_362pe", 2),
            "AstralAutomatonsSummonedThisGame": ench("BG_TTN_401pe", 1),
            "BeetleAttackBuff": ench("BG31_808pe", 1),
            "BeetleHealthBuff": ench("BG31_808pe", 2),
            "SanlaynScribesDeadThisGame": ench("BGDUO31_208pe", 1),
            "DeepBluesPlayed": ench("BG26_502pe", 1),
            "WhelpAttackBuff": ench("BG34_402pe", 1),
            "WhelpHealthBuff": ench("BG34_402pe", 2),
            "BloodGemAttackBonus": m.bloodGem.attack,
            "BloodGemHealthBonus": m.bloodGem.health,
            "TavernSpellsCastThisGame": tag(3088),
            "SpellsCastThisGame": tag(1780),
            "FrostlingBonus": tag(2878),
            "PiratesPlayedThisGame": tag(2358),
            "PiratesSummonedThisGame": tag(3685),
            "BeastsSummonedThisGame": tag(3962),
            "MagnetizedThisGame": tag(3670),
            "ElementalAttackBuff": tag(4002),
            "ElementalHealthBuff": tag(4001),
            "TavernSpellAttackBuff": m.tavernSpellBuff.attack,
            "TavernSpellHealthBuff": m.tavernSpellBuff.health,
            "GoldSpentThisGame": tag(4212),
            // Firestone reads 3873, HDT 3236; they agreed in the captures (mapping §9.7).
            "BattlecriesTriggeredThisGame": m.counters[3873] ?? tag(3236),
            "DeathrattlesTriggeredThisGame": tag(4639),
            "FriendlyMinionsDeadLastCombat": tag(2717),
            "VolumizerAttackBuff": tag(4468),
            "VolumizerHealthBuff": tag(4469),
            "GoldenMinionsPlayedThisGame": tag(4799),
            "CardsDiscardedThisGame": tag(4768),
            "TastyLobstersBuff": tag(4803),
        ]
    }

    /// Choral Mrrrglr's buff lives in `BG26_354e` on a board minion; halved when its creator is golden.
    private static func choralBuff(_ store: EntityStore, _ index: AttachmentIndex, board: [Entity]) -> BGStatBuff? {
        var buff: BGStatBuff?
        for minion in board {
            for enchantment in index.attached(to: minion.id) where enchantment.cardID == SpecialCard.choralEnchantment {
                let golden = enchantment.int(.creator).flatMap { store[$0]?.int(.premium) } == 1
                let divisor = golden ? 2 : 1
                buff = BGStatBuff(
                    attack: (enchantment.int(.tagScriptDataNum1) ?? 0) / divisor,
                    health: (enchantment.int(.tagScriptDataNum2) ?? 0) / divisor
                )
            }
        }
        return buff
    }
}

/// Enchantments by the entity they're attached to, built once per input.
private struct AttachmentIndex {
    /// Every entity with `ATTACHED`, not removed from the game, by entity ID.
    let all: [Entity]
    private let byTarget: [Int: [Entity]]

    init(_ store: EntityStore) {
        all = store.entities.values
            .filter { $0.int(.attached) != nil && $0.name(.zone) != "REMOVEDFROMGAME" }
            .sorted { $0.id < $1.id }
        byTarget = Dictionary(grouping: all) { $0.int(.attached) ?? 0 }
    }

    func attached(to id: Int) -> [Entity] { byTarget[id] ?? [] }
}

/// Card IDs the builder special-cases (from `@firestone-hs/reference-data` CardIds).
private enum SpecialCard {
    static let rebornRites = "TB_BaconShop_HP_024"
    static let embraceYourRage = "TB_BaconShop_HP_103"
    static let lockAndLoad = "BG22_HERO_000p_Alt"
    /// Hero powers whose target is the minion carrying this enchantment: Rapid Reanimation, Glorious Gloop.
    static let markedMinionHeroPowers = ["BG25_HERO_103p": "BG25_HERO_103pe", "BGDUO_HERO_101p": "BGDUO_HERO_101pe2"]
    static let choralEnchantment = "BG26_354e"
    static let lovesickBalladist = "BG26_814"
    static let serenadedEnchantment = "BG26_814e"
    /// Polarizing Beatboxer and Clunker Junker: the simulator also needs the magnetized card by dbfId.
    static let dbfIDEnchantments: Set<String> = ["BG26_149e", "BG29_503e"]
}

// Tags the builder reads. Named ones resolve through the generated enum table.
private enum T {
    static let taunt = GameTag(token: "TAUNT")
    static let divineShield = GameTag(token: "DIVINE_SHIELD")
    static let poisonous = GameTag(token: "POISONOUS")
    static let venomous = GameTag(token: "VENOMOUS")
    static let reborn = GameTag(token: "REBORN")
    static let stealth = GameTag(token: "STEALTH")
    static let windfury = GameTag(token: "WINDFURY")
    static let megaWindfury = GameTag(token: "MEGA_WINDFURY")
    static let unplayableVisuals = GameTag(token: "UNPLAYABLE_VISUALS")
    static let literallyUnplayable = GameTag(token: "LITERALLY_UNPLAYABLE")
    static let modularPart1 = GameTag(token: "MODULAR_ENTITY_PART_1")
    static let modularPart2 = GameTag(token: "MODULAR_ENTITY_PART_2")
    static let numTurnsInPlay = GameTag(token: "NUM_TURNS_IN_PLAY")
    static let cardTarget = GameTag(token: "CARD_TARGET")
    static let magnetic = GameTag(token: "MAGNETIC")
    static let creatorDbID = GameTag(token: "CREATOR_DBID")
    static let yamatoCannon = GameTag.id(4036)
    /// Not in HearthstoneJSON's enums; the number is reference-data's.
    static let entityAsEnchantment = GameTag.id(2787)

    static let named: [GameTag] = [
        taunt, divineShield, poisonous, venomous, reborn, stealth, windfury, megaWindfury, unplayableVisuals,
        literallyUnplayable, modularPart1, modularPart2, numTurnsInPlay, cardTarget, magnetic, creatorDbID,
    ]
}

extension BattleInputBuilder {
    /// Tag names the builder reads that the pinned enum table doesn't know (should be empty).
    public static var unresolvedTagNames: [String] {
        T.named.compactMap { if case .unresolved(let name) = $0 { name } else { nil } }
    }
}

extension GameTag {
    fileprivate static let attached = GameTag.id(40)
    fileprivate static let creator = GameTag.id(313)
    fileprivate static let tagScriptDataNum1 = GameTag.id(2)
    fileprivate static let tagScriptDataNum2 = GameTag.id(3)
    /// `TAG_SCRIPT_DATA_NUM_1…6`.
    fileprivate static let scriptDataTags: [GameTag] = [2, 3, 2889, 2919, 2920, 2921].map { GameTag.id($0) }
}
