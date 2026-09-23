import Foundation

/// Which Battlegrounds pool: solo leaves out the Duos-exclusive cards.
public enum PoolMode: String, Codable, Hashable, Sendable {
    case solo
    case duos
}

/// Which layer put a card in the pool (or set its value).
public enum PoolSource: String, Codable, Hashable, Sendable {
    /// The build's card data, unchanged.
    case cardData
    /// HSReplay's live meta period overrode the card data.
    case metaPeriod
    /// Our override file.
    case overrides
    /// The game flagged it as a pool minion during a game, and none of the above had it.
    case sessionDrift
}

/// A minion Bob can sell in this patch's lobbies.
public struct PoolMinion: Codable, Hashable, Sendable {
    public var cardID: String
    public var dbfID: Int
    public var name: String
    /// Tavern tier.
    public var tier: Int
    /// Its tribes that are in rotation; empty for a neutral or all-type minion.
    public var tribes: [HS.Race]
    /// An all-type (Menagerie) minion: in every lobby, never tribe evidence.
    public var isAllTribes: Bool
    /// The lobby needs at least one of these tribes for the minion to be in it: its own
    /// tribes, or the tribe a neutral minion is gated to. Empty means every lobby.
    public var lobbyGate: [HS.Race]
    /// It has tribes, none of them in rotation: no lobby should offer it (a pool drift).
    public var isOutOfRotation: Bool
    public var isDuosOnly: Bool
    public var source: PoolSource
}

/// A tribe forced into every lobby until a date.
public struct ForcedTribe: Codable, Hashable, Sendable {
    public var tribe: HS.Race
    /// Nil means no end date.
    public var until: Date?

    public init(tribe: HS.Race, until: Date?) {
        self.tribe = tribe
        self.until = until
    }

    public func isForced(at date: Date?) -> Bool {
        guard let until, let date else { return true }
        return date < until
    }
}

/// Which lobbies a hero is offered in, as tribes.
public struct HeroTribeRule: Codable, Hashable, Sendable {
    /// Offered only when one of these is in the lobby (empty: no requirement).
    public var needsAny: [HS.Race]
    /// Never offered when one of these is in the lobby.
    public var bannedWithAny: [HS.Race]

    public init(needsAny: [HS.Race] = [], bannedWithAny: [HS.Race] = []) {
        self.needsAny = needsAny
        self.bannedWithAny = bannedWithAny
    }
}

/// A card the game flagged as a pool minion that our pool didn't have: it was added for
/// the game it was seen in. Fold these into the override file after a patch.
public struct PoolDrift: Codable, Hashable, Sendable {
    public var cardID: String
    public var name: String?
    public var tier: Int
    /// The game it was seen in.
    public var gameSeed: Int?

    public init(cardID: String, name: String?, tier: Int, gameSeed: Int?) {
        self.cardID = cardID
        self.name = name
        self.tier = tier
        self.gameSeed = gameSeed
    }
}

/// The live Battlegrounds minion pool of one patch and mode.
///
/// Composed from four layers, later ones winning (research §A.8):
/// 1. the build's card data: `TECH_LEVEL > 0` and `IS_BACON_POOL_MINION`;
/// 2. HSReplay's live meta period: per-card tag overrides and the tribes in rotation;
/// 3. our override file: per-card pool values, tribes per lobby, forced tribes, tribe gates;
/// 4. during a game, `adopt(_:tier:)` for cards the game itself flags as pool minions.
///
/// A minion is in the pool when its final pool value is 1, it has a tribe in rotation (or
/// none, or all), it isn't Duos-only in a solo game, and it isn't a non-shop card.
public struct MinionPool: Sendable {
    /// Where the pool came from, for stale indicators.
    public struct Provenance: Hashable, Sendable {
        public var cardBuild: Int?
        /// The card data is for the running build.
        public var cardDataIsExact: Bool
        public var metaPeriodName: String?
        /// The meta period is the last good or the bundled copy, not a fresh fetch.
        public var metaPeriodIsStale: Bool
        public var overridesPatch: String?

        public init(
            cardBuild: Int?, cardDataIsExact: Bool = true, metaPeriodName: String? = nil, metaPeriodIsStale: Bool = false,
            overridesPatch: String? = nil
        ) {
            self.cardBuild = cardBuild
            self.cardDataIsExact = cardDataIsExact
            self.metaPeriodName = metaPeriodName
            self.metaPeriodIsStale = metaPeriodIsStale
            self.overridesPatch = overridesPatch
        }

        public var isStale: Bool { !cardDataIsExact || metaPeriodIsStale || metaPeriodName == nil }
    }

    public let cards: CardDB
    public let mode: PoolMode
    /// By card ID (normal, not golden).
    public private(set) var minions: [String: PoolMinion]
    /// Tavern spell card IDs in the pool.
    public let spells: Set<String>
    public let tribesInRotation: [HS.Race]
    public let tribesPerLobby: Int
    public let forcedTribes: [ForcedTribe]
    /// By the hero's base card ID.
    public let heroRules: [String: HeroTribeRule]
    public var provenance: Provenance

    static let poolMinionTag = 1456
    static let techLevelTag = 1440
    static let poolSpellTag = 3081
    /// Tribes per lobby when no source says (Firestone `TOTAL_RACES_IN_GAME`, and every captured lobby).
    public static let defaultTribesPerLobby = 5

    /// Composes the pool. With neither a meta period nor overrides, it is the card data's
    /// flags alone, with every tribe that appears among them in rotation.
    public static func compose(
        cards: CardDB, metaPeriod: MetaPeriod?, overrides: PoolOverrides?, mode: PoolMode = .solo,
        provenance: Provenance? = nil
    ) -> MinionPool {
        let rotation = rotation(cards: cards, metaPeriod: metaPeriod, overrides: overrides)
        let rotationSet = Set(rotation)
        let nonShop = Set(overrides?.nonShop ?? [])
        let gates = (overrides?.minionTribeGates ?? [:]).mapValues { $0.compactMap { HS.Race(name: $0) } }

        var minions: [String: PoolMinion] = [:]
        var spells: Set<String> = []
        for card in cards.cards {
            if card.battlegroundsNormalDbfId != nil || nonShop.contains(card.id) { continue }
            let duosOnly = card.isBattlegroundsDuosExclusive ?? false
            if duosOnly, mode == .solo { continue }
            switch card.type {
            case "MINION":
                var tier = card.techLevel ?? 0
                if let value = metaPeriod?.override(dbfID: card.dbfId, tag: techLevelTag) { tier = value }
                guard tier > 0 else { continue }
                var flag = (card.isBattlegroundsPoolMinion ?? false) ? 1 : 0
                var source = PoolSource.cardData
                if let value = metaPeriod?.override(dbfID: card.dbfId, tag: poolMinionTag) {
                    flag = value
                    source = .metaPeriod
                }
                if let value = overrides?.minionPool[card.id] {
                    flag = value
                    source = .overrides
                }
                guard flag == 1 else { continue }
                let minion = poolMinion(card, tier: tier, rotation: rotationSet, gate: gates[card.id], source: source)
                guard !minion.isOutOfRotation else { continue }
                minions[card.id] = minion
            case "BATTLEGROUND_SPELL":
                var flag = (card.isBattlegroundsPoolSpell ?? false) ? 1 : 0
                if let value = metaPeriod?.override(dbfID: card.dbfId, tag: poolSpellTag) { flag = value }
                if let value = overrides?.spellPool[card.id] { flag = value }
                if flag == 1 { spells.insert(card.id) }
            default:
                continue
            }
        }

        var heroRules: [String: HeroTribeRule] = [:]
        for (hero, rule) in overrides?.heroTribeRules ?? [:] {
            heroRules[hero] = HeroTribeRule(
                needsAny: rule.needsAny.compactMap { HS.Race(name: $0) },
                bannedWithAny: rule.bannedWithAny.compactMap { HS.Race(name: $0) }
            )
        }
        let forced = (overrides?.forcedTribes ?? []).compactMap { forced in
            HS.Race(name: forced.tribe).map { ForcedTribe(tribe: $0, until: forced.until) }
        }.filter { rotationSet.contains($0.tribe) }

        return MinionPool(
            cards: cards, mode: mode, minions: minions, spells: spells, tribesInRotation: rotation,
            tribesPerLobby: overrides?.tribesPerLobby ?? defaultTribesPerLobby, forcedTribes: forced,
            heroRules: heroRules,
            provenance: provenance ?? Provenance(
                cardBuild: cards.build, metaPeriodName: metaPeriod?.name, overridesPatch: overrides?.patch
            )
        )
    }

    /// The tribes in rotation: from whichever of the meta period and the override file is
    /// newer (a new meta period after our file was written knows about a later patch);
    /// with neither, every tribe the flagged minions have.
    static func rotation(cards: CardDB, metaPeriod: MetaPeriod?, overrides: PoolOverrides?) -> [HS.Race] {
        let fromOverrides = overrides?.tribesInRotation?.compactMap { HS.Race(name: $0) }
        let fromMeta = metaPeriod?.tribesInRotation
        let chosen: [HS.Race]? = switch (fromMeta, fromOverrides) {
        case (let meta?, let ours?):
            (metaPeriod?.periodStart ?? .distantPast) > (overrides?.validFrom ?? .distantPast) ? meta : ours
        case (let meta?, nil): meta
        case (nil, let ours?): ours
        case (nil, nil): nil
        }
        if let chosen { return Array(Set(chosen).subtracting([.all])).sorted(by: tribeOrder) }
        var seen: Set<HS.Race> = []
        for card in cards.cards where card.type == "MINION" && (card.techLevel ?? 0) > 0
            && card.isBattlegroundsPoolMinion == true && card.battlegroundsNormalDbfId == nil {
            seen.formUnion(card.tribes)
        }
        return Array(seen.subtracting([.all])).sorted(by: tribeOrder)
    }

    /// Tribes in name order, so every list of them reads the same.
    static func tribeOrder(_ a: HS.Race, _ b: HS.Race) -> Bool { a.description < b.description }

    static func poolMinion(
        _ card: Card, tier: Int, rotation: Set<HS.Race>, gate: [HS.Race]?, source: PoolSource
    ) -> PoolMinion {
        let races = card.tribes
        let isAll = races.contains(.all)
        let live = isAll ? [] : races.filter(rotation.contains).sorted(by: tribeOrder)
        let outOfRotation = !isAll && !races.isEmpty && live.isEmpty
        let lobbyGate = isAll ? [] : (live.isEmpty ? (gate ?? []).filter(rotation.contains) : live)
        return PoolMinion(
            cardID: card.id, dbfID: card.dbfId, name: card.name, tier: tier, tribes: live, isAllTribes: isAll,
            lobbyGate: lobbyGate, isOutOfRotation: outOfRotation,
            isDuosOnly: card.isBattlegroundsDuosExclusive ?? false, source: source
        )
    }

    // MARK: - Lookups

    /// The normal card of a golden minion (`…_G`), else the card itself.
    public func baseCardID(_ cardID: String) -> String {
        if let normal = cards[cardID]?.battlegroundsNormalDbfId, let card = cards.card(dbfID: normal) {
            return card.id
        }
        if cardID.hasSuffix("_G"), cards[cardID] == nil { return String(cardID.dropLast(2)) }
        return cardID
    }

    /// The pool entry for a card, golden or not.
    public func minion(_ cardID: String) -> PoolMinion? { minions[baseCardID(cardID)] }

    public func contains(_ cardID: String) -> Bool { minion(cardID) != nil }

    /// The tribes forced into every lobby at `date` (all of them when the date is unknown).
    public func forcedTribes(at date: Date?) -> [HS.Race] {
        forcedTribes.filter { $0.isForced(at: date) }.map(\.tribe)
    }

    /// The hero a skin belongs to, else the hero itself.
    public func baseHeroCardID(_ cardID: String) -> String {
        if let parent = cards[cardID]?.battlegroundsSkinParentId, let card = cards.card(dbfID: parent) { return card.id }
        return cardID
    }

    public func heroRule(_ heroCardID: String) -> HeroTribeRule? { heroRules[baseHeroCardID(heroCardID)] }

    // MARK: - Self-heal

    /// Adds a card the game flagged as a pool minion (`IS_BACON_POOL_MINION=1`) that the
    /// pool lacks, at the tier the game gave it. Returns the drift to report, or nil when the
    /// card is already in the pool or isn't a minion to add. Cards are never removed this way.
    public mutating func adopt(_ cardID: String, tier: Int?, gameSeed: Int? = nil) -> PoolDrift? {
        let base = baseCardID(cardID)
        guard minions[base] == nil else { return nil }
        let card = cards[base]
        guard card.map({ $0.type == "MINION" }) ?? true, !base.isEmpty else { return nil }
        let level = tier ?? card?.techLevel ?? 0
        guard level > 0 else { return nil }
        let minion = card.map {
            Self.poolMinion($0, tier: level, rotation: Set(tribesInRotation), gate: nil, source: .sessionDrift)
        } ?? PoolMinion(
            cardID: base, dbfID: 0, name: base, tier: level, tribes: [], isAllTribes: false, lobbyGate: [],
            isOutOfRotation: false, isDuosOnly: false, source: .sessionDrift
        )
        minions[base] = minion
        return PoolDrift(cardID: base, name: card?.name, tier: level, gameSeed: gameSeed)
    }
}
