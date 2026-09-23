import Foundation

// The raw build data: Firestone's comp stats and curated comp strategies, and our own
// override file. `BuildCatalog.compose` turns them into build definitions.
// See docs/research/meta-comps-2026-09.md §7-8 and aberrations-2026-09.md §8.

// MARK: - Firestone comp stats

/// Firestone's Battlegrounds comp stats
/// (`https://static.zerotoheroes.com/api/bgs/comp-stats/<period>/overview-from-hourly.gz.json`),
/// reduced to what build detection needs: per archetype, its placement numbers and how
/// often each card is on a sampled final board.
///
/// The raw file is about 60 MB (5 MB gzipped) because it carries every sampled board's full
/// tags, so the app caches and bundles this derived form instead (`derive(fromFirestone:)`).
public struct FirestoneCompStats: Codable, Hashable, Sendable {
    public struct Placement: Codable, Hashable, Sendable {
        /// MMR percentile bucket: 100 is all players, 10 the top 10%.
        public var mmr: Int
        public var dataPoints: Int
        public var placement: Double

        public init(mmr: Int, dataPoints: Int, placement: Double) {
            self.mmr = mmr
            self.dataPoints = dataPoints
            self.placement = placement
        }
    }

    public struct Comp: Codable, Hashable, Sendable {
        /// Firestone's archetype ID, e.g. `beast_lobster`.
        public var archetype: String
        /// Games whose final board Firestone tagged with this archetype.
        public var dataPoints: Int
        /// Over those games only (players who died early are under-represented).
        public var averagePlacement: Double
        public var averagePlacementAtMmr: [Placement]
        /// Final boards sampled (about 1,000 per comp).
        public var sampledBoards: Int
        /// Card ID -> how many sampled boards had it. Goldens with an `_G` suffix are folded
        /// into their base card; `TB_BaconUps_*` goldens stay as they are (the catalog folds
        /// them with the card data). Cards on under 2% of boards are left out.
        public var boardsWithCard: [String: Int]

        public init(
            archetype: String, dataPoints: Int, averagePlacement: Double, averagePlacementAtMmr: [Placement] = [],
            sampledBoards: Int, boardsWithCard: [String: Int]
        ) {
            self.archetype = archetype
            self.dataPoints = dataPoints
            self.averagePlacement = averagePlacement
            self.averagePlacementAtMmr = averagePlacementAtMmr
            self.sampledBoards = sampledBoards
            self.boardsWithCard = boardsWithCard
        }

        /// The average placement in one MMR bucket.
        public func averagePlacement(mmr: Int) -> Double? {
            averagePlacementAtMmr.first { $0.mmr == mmr }?.placement
        }
    }

    /// Firestone's `lastUpdateDate` (ISO 8601).
    public var lastUpdateDate: String
    /// `last-patch`, `past-seven`, `past-three` or `all-time`.
    public var timePeriod: String
    public var dataPoints: Int
    public var comps: [Comp]

    public init(lastUpdateDate: String, timePeriod: String, dataPoints: Int, comps: [Comp]) {
        self.lastUpdateDate = lastUpdateDate
        self.timePeriod = timePeriod
        self.dataPoints = dataPoints
        self.comps = comps
    }

    public var updatedAt: Date? { FirestoneDate.parse(lastUpdateDate) }

    /// Decodes the derived form (what the cache and the bundle hold).
    public init(json: Data) throws {
        self = try JSONDecoder().decode(FirestoneCompStats.self, from: json)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// Reduces Firestone's raw comp-stats file. Throws on anything that isn't one (such as a
    /// CDN error page).
    public static func derive(fromFirestone json: Data, minimumShare: Double = 0.02) throws -> FirestoneCompStats {
        let raw = try JSONDecoder().decode(RawFile.self, from: json)
        let comps = raw.compStats.map { comp -> Comp in
            var boards = 0
            var counts: [String: Int] = [:]
            for hero in comp.heroStats ?? [] {
                for board in hero.finalBoards ?? [] {
                    boards += 1
                    var seen: Set<String> = []
                    for minion in board.finalComp?.board ?? [] {
                        guard var id = minion.cardID, !id.isEmpty else { continue }
                        if id.hasSuffix("_G") { id.removeLast(2) }
                        seen.insert(id)
                    }
                    for id in seen { counts[id, default: 0] += 1 }
                }
            }
            let floor = Double(boards) * minimumShare
            return Comp(
                archetype: comp.archetype, dataPoints: comp.dataPoints ?? 0,
                averagePlacement: comp.averagePlacement ?? 0,
                averagePlacementAtMmr: (comp.averagePlacementAtMmr ?? []).compactMap { entry in
                    guard let mmr = entry.mmr, let placement = entry.placement else { return nil }
                    return Placement(mmr: mmr, dataPoints: entry.dataPoints ?? 0, placement: placement)
                },
                sampledBoards: boards,
                boardsWithCard: counts.filter { Double($0.value) >= floor && $0.value > 0 }
            )
        }
        return FirestoneCompStats(
            lastUpdateDate: raw.lastUpdateDate ?? "", timePeriod: raw.timePeriod ?? "",
            dataPoints: raw.dataPoints ?? 0, comps: comps.sorted { $0.archetype < $1.archetype }
        )
    }

    /// The copy shipped with the app (derived from Firestone's `last-patch` file).
    public static func bundled() -> FirestoneCompStats? {
        guard let url = HSDataResources.url("bg-pool/builds/firestone-comp-stats.json") else { return nil }
        return try? FirestoneCompStats(json: Data(contentsOf: url))
    }

    // Only the fields used; the per-minion tags and everything else are skipped.
    private struct RawFile: Decodable {
        var compStats: [RawComp]
        var lastUpdateDate: String?
        var dataPoints: Int?
        var timePeriod: String?
    }

    private struct RawComp: Decodable {
        var archetype: String
        var dataPoints: Int?
        var averagePlacement: Double?
        var averagePlacementAtMmr: [RawPlacement]?
        var heroStats: [RawHero]?
    }

    private struct RawPlacement: Decodable {
        var mmr: Int?
        var dataPoints: Int?
        var placement: Double?
    }

    private struct RawHero: Decodable {
        var finalBoards: [RawBoard]?
    }

    private struct RawBoard: Decodable {
        var finalComp: RawFinalComp?
    }

    private struct RawFinalComp: Decodable {
        var board: [RawMinion]?
    }

    private struct RawMinion: Decodable {
        var cardID: String?
    }
}

// MARK: - Firestone curated strategies

/// Firestone's curated comp strategies
/// (`https://static.zerotoheroes.com/hearthstone/data/battlegrounds-strategies/bgs-comps-strategies.gz.json`):
/// per comp, its CORE / ADDON / CYCLE cards, difficulty, power level and tips.
///
/// The file is hand-maintained. It has blank placeholder entries, every `cardId` is
/// `#N/A` (cards are resolved by name) and `patchNumber` is a number or an empty string.
public struct FirestoneStrategies: Hashable, Sendable {
    public struct Card: Decodable, Hashable, Sendable {
        /// Usually `#N/A`.
        public var cardId: String?
        public var name: String
        /// `CORE`, `ADDON` or `CYCLE`.
        public var status: String

        public init(cardId: String? = nil, name: String, status: String) {
            self.cardId = cardId
            self.name = name
            self.status = status
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            cardId = try c.decodeIfPresent(String.self, forKey: .cardId)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        }

        private enum CodingKeys: String, CodingKey { case cardId, name, status }
    }

    public struct Tip: Decodable, Hashable, Sendable {
        public var author: String?
        public var tip: String?
        public var whenToCommit: String?
        public var date: String?

        public init(author: String? = nil, tip: String?, whenToCommit: String?, date: String? = nil) {
            self.author = author
            self.tip = tip
            self.whenToCommit = whenToCommit
            self.date = date
        }
    }

    public struct Comp: Decodable, Hashable, Sendable {
        public var compId: String
        public var name: String
        public var patchNumber: Int?
        public var cards: [Card]
        public var difficulty: String?
        public var powerLevel: String?
        public var tips: [Tip]

        public init(
            compId: String, name: String, patchNumber: Int? = nil, cards: [Card], difficulty: String? = nil,
            powerLevel: String? = nil, tips: [Tip] = []
        ) {
            self.compId = compId
            self.name = name
            self.patchNumber = patchNumber
            self.cards = cards
            self.difficulty = difficulty
            self.powerLevel = powerLevel
            self.tips = tips
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            compId = try c.decodeIfPresent(String.self, forKey: .compId) ?? ""
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            patchNumber = (try? c.decodeIfPresent(Int.self, forKey: .patchNumber))
                ?? (try? c.decodeIfPresent(String.self, forKey: .patchNumber)).flatMap { $0.flatMap(Int.init) }
            cards = try c.decodeIfPresent([Card].self, forKey: .cards) ?? []
            difficulty = try c.decodeIfPresent(String.self, forKey: .difficulty).flatMap { $0.isEmpty ? nil : $0 }
            powerLevel = try c.decodeIfPresent(String.self, forKey: .powerLevel).flatMap { $0.isEmpty ? nil : $0 }
            tips = try c.decodeIfPresent([Tip].self, forKey: .tips) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case compId, name, patchNumber, cards, difficulty, powerLevel, tips
        }
    }

    /// Only the real comps: the blank placeholders are dropped.
    public var comps: [Comp]

    public init(comps: [Comp]) {
        self.comps = comps.filter { !$0.compId.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Decodes the raw file (a JSON array). Throws on anything that isn't one.
    public init(json: Data) throws {
        self.init(comps: try JSONDecoder().decode([Comp].self, from: json))
    }

    public func comp(_ id: String) -> Comp? { comps.first { $0.compId == id } }

    /// The copy shipped with the app.
    public static func bundled() -> FirestoneStrategies? {
        guard let url = HSDataResources.url("bg-pool/builds/firestone-comp-strategies.json") else { return nil }
        return try? FirestoneStrategies(json: Data(contentsOf: url))
    }
}

// `FirestoneDate` (shared with the hero stats) is in HeroStats.swift.

// MARK: - Our override file

/// Our maintained build file (`Resources/bg-pool/builds/overrides/<patch>.json`): builds for
/// tribes the sources don't cover yet (Aberrations in 36.6.1), and source builds to leave out.
///
/// A build here is used when no source build covers its first tribe (`use: when_sources_lack_tribe`,
/// the default), so it retires by itself once Firestone publishes an archetype for the tribe;
/// `use: always` keeps it regardless (and replaces a source build with the same ID).
public struct BuildOverrides: Codable, Hashable, Sendable {
    public enum Use: String, Codable, Hashable, Sendable {
        case whenSourcesLackTribe = "when_sources_lack_tribe"
        case always
    }

    public struct Build: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        /// `Race` names; the first is the tribe the build is for.
        public var tribes: [String]
        public var use: Use
        public var core: [String]
        public var addons: [String]
        public var whenToCommit: String?
        public var tip: String?
        /// How the build is known: `data-sample`, `video`, `community`, `card-text`.
        public var evidence: [String]
        /// Only in games with this Deity (card ID).
        public var requiresDeity: String?

        public init(
            id: String, name: String, tribes: [String], use: Use = .whenSourcesLackTribe, core: [String],
            addons: [String] = [], whenToCommit: String? = nil, tip: String? = nil, evidence: [String] = [],
            requiresDeity: String? = nil
        ) {
            self.id = id
            self.name = name
            self.tribes = tribes
            self.use = use
            self.core = core
            self.addons = addons
            self.whenToCommit = whenToCommit
            self.tip = tip
            self.evidence = evidence
            self.requiresDeity = requiresDeity
        }

        private enum CodingKeys: String, CodingKey {
            case id, name, tribes, use, core, addons, tip, evidence
            case whenToCommit = "when_to_commit"
            case requiresDeity = "requires_deity"
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            tribes = try c.decodeIfPresent([String].self, forKey: .tribes) ?? []
            use = try c.decodeIfPresent(Use.self, forKey: .use) ?? .whenSourcesLackTribe
            core = try c.decode([String].self, forKey: .core)
            addons = try c.decodeIfPresent([String].self, forKey: .addons) ?? []
            whenToCommit = try c.decodeIfPresent(String.self, forKey: .whenToCommit)
            tip = try c.decodeIfPresent(String.self, forKey: .tip)
            evidence = try c.decodeIfPresent([String].self, forKey: .evidence) ?? []
            requiresDeity = try c.decodeIfPresent(String.self, forKey: .requiresDeity)
        }
    }

    public var patch: String
    /// When the patch went live; the newest file whose date has come applies.
    public var validFrom: Date
    public var builds: [Build]
    /// Source build IDs to leave out.
    public var disabled: [String]

    public init(patch: String, validFrom: Date, builds: [Build] = [], disabled: [String] = []) {
        self.patch = patch
        self.validFrom = validFrom
        self.builds = builds
        self.disabled = disabled
    }

    private enum CodingKeys: String, CodingKey {
        case patch, builds, disabled
        case validFrom = "valid_from"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        patch = try c.decode(String.self, forKey: .patch)
        validFrom = try c.decode(Date.self, forKey: .validFrom)
        builds = try c.decodeIfPresent([Build].self, forKey: .builds) ?? []
        disabled = try c.decodeIfPresent([String].self, forKey: .disabled) ?? []
    }

    /// Decodes one file (snake_case keys, ISO 8601 dates). Unknown keys, such as notes, are ignored.
    public init(json: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self = try decoder.decode(BuildOverrides.self, from: json)
    }

    /// The files shipped with the app.
    public static func bundled() -> [BuildOverrides] {
        HSDataResources.url("bg-pool/builds/overrides").map(load(directory:)) ?? []
    }

    /// Every readable `*.json` file in `directory`.
    public static func load(directory: URL) -> [BuildOverrides] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? BuildOverrides(json: Data(contentsOf: $0)) }
    }

    /// `~/Library/Application Support/TavernLens/Builds/overrides`: drop a newer file here to
    /// use it before the app is rebuilt.
    public static var localDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "TavernLens/Builds/overrides", directoryHint: .isDirectory)
    }

    /// The file that applies at `date`: the newest `validFrom` not after it (a local file
    /// wins a tie), else the oldest file when none has started yet.
    public static func current(
        at date: Date = Date(), bundled: [BuildOverrides] = bundled(),
        local: [BuildOverrides] = load(directory: localDirectory)
    ) -> BuildOverrides? {
        var best: BuildOverrides?
        for file in bundled + local where file.validFrom <= date {
            if best.map({ file.validFrom >= $0.validFrom }) ?? true { best = file }
        }
        return best ?? (bundled + local).min { $0.validFrom < $1.validFrom }
    }
}
