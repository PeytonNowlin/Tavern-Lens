import Foundation

/// One build (comp) a player can go for: the cards that define it, the ones that fit it,
/// and how to play it.
public struct BuildDefinition: Codable, Hashable, Sendable {
    public enum Source: String, Codable, Hashable, Sendable {
        /// Firestone's comp stats and curated strategies.
        case firestone
        /// Our override file.
        case overrides
    }

    /// Firestone's archetype ID or ours (`beast_lobster`, `aberration_discard_deity`).
    public var id: String
    public var name: String
    /// The tribes it's built on, the defining one first; empty for a tribe-agnostic build.
    public var tribes: [HS.Race]
    /// Base card IDs that define it: the curated core cards first, then the cards on at least
    /// 60% of sampled final boards. Only cards in the current pool.
    public var core: [String]
    /// Base card IDs that fit it: the curated add-on and cycle cards, then the cards on 20-59%
    /// of sampled final boards. Only cards in the current pool.
    public var addons: [String]
    public var whenToCommit: String?
    public var tip: String?
    /// Firestone's curated difficulty (`Easy`, `Medium`, `Hard`) and power level (`S` … `D`).
    public var difficulty: String?
    public var powerLevel: String?
    /// Over games that ended on this build, all players; nil without stats.
    public var averagePlacement: Double?
    /// The same for the top 10% of players.
    public var averagePlacementTop10: Double?
    /// Share of comp-tagged games.
    public var popularity: Double?
    /// Card IDs the sources list that the current pool no longer has (removed or rotated out).
    public var removedCards: [String]
    /// Only in games with this Deity (dbfId).
    public var requiresDeityDbfID: Int?
    /// How our override builds are known (`card-text`, `community`, …); empty for source builds.
    public var evidence: [String]
    public var source: Source

    public init(
        id: String, name: String, tribes: [HS.Race], core: [String], addons: [String] = [],
        whenToCommit: String? = nil, tip: String? = nil, difficulty: String? = nil, powerLevel: String? = nil,
        averagePlacement: Double? = nil, averagePlacementTop10: Double? = nil, popularity: Double? = nil,
        removedCards: [String] = [], requiresDeityDbfID: Int? = nil, evidence: [String] = [],
        source: Source = .firestone
    ) {
        self.id = id
        self.name = name
        self.tribes = tribes
        self.core = core
        self.addons = addons
        self.whenToCommit = whenToCommit
        self.tip = tip
        self.difficulty = difficulty
        self.powerLevel = powerLevel
        self.averagePlacement = averagePlacement
        self.averagePlacementTop10 = averagePlacementTop10
        self.popularity = popularity
        self.removedCards = removedCards
        self.requiresDeityDbfID = requiresDeityDbfID
        self.evidence = evidence
        self.source = source
    }
}

/// The builds of the current patch: Firestone's comps plus our override file's, with every
/// card the current minion pool no longer has taken out, and builds that lost their core
/// left out.
public struct BuildCatalog: Hashable, Sendable {
    /// Where the builds came from, for stale indicators.
    public struct Provenance: Hashable, Sendable {
        /// Firestone's `lastUpdateDate` of the comp stats.
        public var statsUpdated: String?
        public var statsTimePeriod: String?
        /// The comp stats are the cached or bundled copy, not a fresh fetch.
        public var statsIsStale: Bool
        public var strategiesIsStale: Bool
        public var overridesPatch: String?

        public init(
            statsUpdated: String? = nil, statsTimePeriod: String? = nil, statsIsStale: Bool = false,
            strategiesIsStale: Bool = false, overridesPatch: String? = nil
        ) {
            self.statsUpdated = statsUpdated
            self.statsTimePeriod = statsTimePeriod
            self.statsIsStale = statsIsStale
            self.strategiesIsStale = strategiesIsStale
            self.overridesPatch = overridesPatch
        }

        public var isStale: Bool { statsIsStale || strategiesIsStale || statsUpdated == nil }
    }

    /// A source or override build that isn't used, and why.
    public struct Dropped: Codable, Hashable, Sendable {
        public var id: String
        public var reason: String

        public init(id: String, reason: String) {
            self.id = id
            self.reason = reason
        }
    }

    /// Best average placement first; builds without stats after, by ID.
    public var builds: [BuildDefinition]
    public var dropped: [Dropped]
    public var provenance: Provenance
    /// Golden card ID -> base card ID, for every card the builds name.
    public var goldenToBase: [String: String]

    public init(
        builds: [BuildDefinition], dropped: [Dropped] = [], provenance: Provenance = Provenance(),
        goldenToBase: [String: String] = [:]
    ) {
        self.builds = builds
        self.dropped = dropped
        self.provenance = provenance
        self.goldenToBase = goldenToBase
    }

    public func build(_ id: String) -> BuildDefinition? { builds.first { $0.id == id } }

    /// The base card of a golden (`…_G` or `TB_BaconUps_*`), else the card itself.
    public func baseCardID(_ cardID: String) -> String {
        if let base = goldenToBase[cardID] { return base }
        if cardID.hasSuffix("_G") { return String(cardID.dropLast(2)) }
        return cardID
    }

    /// A card is core in at least this share of sampled final boards (research §7).
    public static let coreShare = 0.6
    /// An add-on in at least this share.
    public static let addonShare = 0.2
    /// Comps with fewer sampled boards than this are noise (Firestone lists a few with 0-2).
    public static let minimumSampledBoards = 50

    /// Composes the catalog.
    ///
    /// - Source builds come from the comp stats (card shares on final boards) and the curated
    ///   strategies (CORE / ADDON / CYCLE cards, tips), joined on the archetype ID. Either can
    ///   be missing.
    /// - Cards the pool doesn't have are taken out. A build is left out when a curated core
    ///   card is gone, or, without curated core cards, when more than half of its core is.
    /// - The override file's builds are added for tribes no remaining source build is for.
    public static func compose(
        stats: FirestoneCompStats?, strategies: FirestoneStrategies?, overrides: BuildOverrides?, pool: MinionPool,
        provenance: Provenance? = nil
    ) -> BuildCatalog {
        let resolver = CardResolver(pool: pool)
        var dropped: [Dropped] = []
        var builds: [BuildDefinition] = []

        let statsByID = Dictionary((stats?.comps ?? []).map { ($0.archetype, $0) }, uniquingKeysWith: { a, _ in a })
        var ids = (stats?.comps ?? []).filter { $0.sampledBoards >= minimumSampledBoards }.map(\.archetype)
        for comp in strategies?.comps ?? [] where !ids.contains(comp.compId) { ids.append(comp.compId) }
        let disabled = Set(overrides?.disabled ?? [])

        for id in ids {
            if disabled.contains(id) {
                dropped.append(Dropped(id: id, reason: "disabled in the override file"))
                continue
            }
            let comp = statsByID[id].flatMap { $0.sampledBoards >= minimumSampledBoards ? $0 : nil }
            let curated = strategies?.comp(id)
            var shares: [String: Double] = [:]
            if let comp, comp.sampledBoards > 0 {
                var folded: [String: Int] = [:]
                for (card, count) in comp.boardsWithCard { folded[resolver.base(card), default: 0] += count }
                shares = folded.mapValues { min(1, Double($0) / Double(comp.sampledBoards)) }
            }
            let byShare = shares.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            var curatedCore: [String] = []
            var curatedAddons: [String] = []
            for card in curated?.cards ?? [] {
                guard let cardID = resolver.resolve(card) else { continue }
                if card.status.uppercased() == "CORE" { curatedCore.append(cardID) } else { curatedAddons.append(cardID) }
            }
            let core = unique(curatedCore + byShare.filter { $0.value >= coreShare }.map(\.key))
            let addons = unique(curatedAddons + byShare.filter { $0.value >= addonShare && $0.value < coreShare }.map(\.key))
                .filter { !core.contains($0) }
            let tip = curated?.tips.first { !($0.tip ?? "").isEmpty || !($0.whenToCommit ?? "").isEmpty }
            let build = BuildDefinition(
                id: id, name: (curated?.name).flatMap { $0.isEmpty ? nil : $0 } ?? displayName(archetype: id),
                tribes: tribes(archetype: id), core: core, addons: addons,
                whenToCommit: tip?.whenToCommit.flatMap { $0.isEmpty ? nil : $0 },
                tip: tip?.tip.flatMap { $0.isEmpty ? nil : $0 },
                difficulty: curated?.difficulty, powerLevel: curated?.powerLevel,
                averagePlacement: comp?.averagePlacement, averagePlacementTop10: comp?.averagePlacement(mmr: 10),
                popularity: comp.flatMap { comp in
                    (stats?.dataPoints ?? 0) > 0 ? Double(comp.dataPoints) / Double(stats!.dataPoints) : nil
                },
                source: .firestone
            )
            switch filtered(build, curatedCore: Set(curatedCore), resolver: resolver) {
            case .success(let kept): builds.append(kept)
            case .failure(let reason): dropped.append(Dropped(id: id, reason: reason.text))
            }
        }

        // Tribes the source builds cover, by their defining tribe.
        let covered = Set(builds.compactMap(\.tribes.first))
        for extra in overrides?.builds ?? [] {
            let tribes = extra.tribes.compactMap { HS.Race(name: $0) }
            if extra.use == .whenSourcesLackTribe, tribes.first.map(covered.contains) ?? true {
                dropped.append(Dropped(id: extra.id, reason: "the sources cover its tribe"))
                continue
            }
            let build = BuildDefinition(
                id: extra.id, name: extra.name, tribes: tribes, core: unique(extra.core.map(resolver.base)),
                addons: unique(extra.addons.map(resolver.base)), whenToCommit: extra.whenToCommit, tip: extra.tip,
                requiresDeityDbfID: extra.requiresDeity.flatMap { pool.cards[$0]?.dbfId },
                evidence: extra.evidence, source: .overrides
            )
            switch filtered(build, curatedCore: Set(build.core), resolver: resolver) {
            case .success(let kept):
                builds.removeAll { $0.id == kept.id }
                builds.append(kept)
            case .failure(let reason):
                dropped.append(Dropped(id: extra.id, reason: reason.text))
            }
        }

        builds.sort { ($0.averagePlacement ?? .infinity, $0.id) < ($1.averagePlacement ?? .infinity, $1.id) }
        var goldenToBase: [String: String] = [:]
        for build in builds {
            for card in build.core + build.addons {
                for golden in resolver.goldens(of: card) { goldenToBase[golden] = card }
            }
        }
        return BuildCatalog(
            builds: builds, dropped: dropped,
            provenance: provenance ?? Provenance(
                statsUpdated: stats?.lastUpdateDate, statsTimePeriod: stats?.timePeriod,
                overridesPatch: overrides?.patch
            ),
            goldenToBase: goldenToBase
        )
    }

    struct DropReason: Error {
        var text: String
    }

    /// Takes out the cards the pool doesn't have; fails when the build lost its core.
    static func filtered(
        _ build: BuildDefinition, curatedCore: Set<String>, resolver: CardResolver
    ) -> Result<BuildDefinition, DropReason> {
        let removedCore = build.core.filter(resolver.isRemoved)
        if let gone = removedCore.first(where: curatedCore.contains) {
            return .failure(DropReason(text: "core card \(gone) (\(resolver.name(gone))) is no longer in the pool"))
        }
        if curatedCore.isEmpty, !build.core.isEmpty, Double(removedCore.count) > Double(build.core.count) / 2 {
            return .failure(DropReason(text: "most of its core is no longer in the pool: \(removedCore.joined(separator: ", "))"))
        }
        var kept = build
        kept.core = build.core.filter { !resolver.isRemoved($0) }
        kept.addons = build.addons.filter { !resolver.isRemoved($0) }
        kept.removedCards = removedCore + build.addons.filter(resolver.isRemoved)
        guard !kept.core.isEmpty else { return .failure(DropReason(text: "no core cards")) }
        return .success(kept)
    }

    /// `beast_lobster` -> `Beast Lobster`.
    static func displayName(archetype: String) -> String {
        archetype.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// The tribe named by an archetype's prefix (`mech_magnet` -> Mech); none for `neutral_…`.
    static func tribes(archetype: String) -> [HS.Race] {
        guard let prefix = archetype.split(separator: "_").first?.uppercased() else { return [] }
        let name = prefix == "MECH" ? "MECHANICAL" : prefix
        guard let race = HS.Race(name: name), race != .all, race != .invalid else { return [] }
        return [race]
    }

    private static func unique(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        return ids.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// Card lookups for composing the catalog: names to IDs, goldens to base cards, pool membership.
struct CardResolver {
    let pool: MinionPool
    /// Normalized name -> the best Battlegrounds card with it.
    private let byName: [String: String]

    init(pool: MinionPool) {
        self.pool = pool
        var candidates: [String: (rank: Int, id: String)] = [:]
        for card in pool.cards.cards where card.battlegroundsNormalDbfId == nil {
            let rank: Int
            if pool.minions[card.id] != nil || pool.spells.contains(card.id) {
                rank = 0
            } else if card.isBattlegroundsPoolMinion == true || card.isBattlegroundsPoolSpell == true {
                rank = 1
            } else if (card.techLevel ?? 0) > 0, card.type == "MINION" || card.type == "BATTLEGROUND_SPELL" {
                rank = 2
            } else {
                continue
            }
            let key = Self.normalize(card.name)
            if let best = candidates[key], (best.rank, best.id) <= (rank, card.id) { continue }
            candidates[key] = (rank, card.id)
        }
        byName = candidates.mapValues(\.id)
    }

    /// A curated card's ID: its `cardId` when it's a real one, else by name.
    func resolve(_ card: FirestoneStrategies.Card) -> String? {
        if let id = card.cardId, !id.isEmpty, id != "#N/A", pool.cards[id] != nil { return base(id) }
        guard !card.name.isEmpty else { return nil }
        return byName[Self.normalize(card.name)]
    }

    func base(_ cardID: String) -> String { pool.baseCardID(cardID) }

    /// The golden IDs of a base card (`…_G` and `TB_BaconUps_*`).
    func goldens(of cardID: String) -> [String] {
        guard let card = pool.cards[cardID] else { return [cardID + "_G"] }
        var ids = [cardID + "_G"]
        if let premium = card.battlegroundsPremiumDbfId, let golden = pool.cards.card(dbfID: premium) {
            ids.append(golden.id)
        }
        return ids
    }

    /// A shop minion or tavern spell the pool doesn't have. Cards the pool never sells
    /// (tokens, trinkets, unknown cards) aren't "removed".
    func isRemoved(_ cardID: String) -> Bool {
        guard let card = pool.cards[cardID] else { return false }
        switch card.type {
        case "MINION":
            return (card.techLevel ?? 0) > 0 && !pool.contains(cardID)
        case "BATTLEGROUND_SPELL":
            return (card.isBattlegroundsPoolSpell ?? false) && !pool.spells.contains(cardID)
        default:
            return false
        }
    }

    func name(_ cardID: String) -> String { pool.cards[cardID]?.name ?? cardID }

    /// Lowercased letters and digits only: "Kalecgos Arcane Aspect" matches "Kalecgos, Arcane Aspect".
    static func normalize(_ name: String) -> String {
        String(name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }
}
