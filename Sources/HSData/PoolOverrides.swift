import Foundation
import os

/// The result of loading a directory of hand-dropped override files: the files that
/// decoded, plus the ones skipped because they were unreadable or malformed.
public struct OverrideLoad<Value: Sendable>: Sendable {
    public struct Skipped: Hashable, Sendable {
        public var file: String
        public var error: String
    }
    public var loaded: [Value]
    public var skipped: [Skipped]

    /// Decodes every `*.json` file in `directory` in file-name order, logging each one it skips.
    static func load(directory: URL, decode: (Data) throws -> Value) -> OverrideLoad {
        let log = Logger(subsystem: "TavernLens", category: "overrides")
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var result = OverrideLoad(loaded: [], skipped: [])
        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                result.loaded.append(try decode(Data(contentsOf: file)))
            } catch {
                log.error("Skipping override file \(file.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
                result.skipped.append(.init(file: file.lastPathComponent, error: String(describing: error)))
            }
        }
        return result
    }
}

/// Our maintained override file for the Battlegrounds minion pool: one JSON file per
/// patch (`Resources/bg-pool/overrides/<patch>.json`), holding the live delta that the
/// build's card data and HSReplay's meta period get wrong or don't say.
///
/// It wins over both on every per-card value. See the patch-day procedure in
/// docs/research/minion-pool-and-tribe-inference.md §A.8.
public struct PoolOverrides: Codable, Hashable, Sendable {
    public struct ForcedTribe: Codable, Hashable, Sendable {
        /// A `Race` name (`ABERRATION`).
        public var tribe: String
        /// When the tribe stops being forced into every lobby; nil means no end date.
        public var until: Date?

        public init(tribe: String, until: Date?) {
            self.tribe = tribe
            self.until = until
        }
    }

    /// A server hotfix applied only to games starting on or after its publication.
    public struct DatedCorrection: Codable, Hashable, Sendable {
        public var patch: String
        public var validFrom: Date
        public var minionPool: [String: Int]
        public var minionTiers: [String: Int]

        public init(
            patch: String, validFrom: Date, minionPool: [String: Int] = [:], minionTiers: [String: Int] = [:]
        ) {
            self.patch = patch
            self.validFrom = validFrom
            self.minionPool = minionPool
            self.minionTiers = minionTiers
        }

        private enum CodingKeys: String, CodingKey {
            case patch
            case validFrom = "valid_from"
            case minionPool = "minion_pool"
            case minionTiers = "minion_tiers"
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            patch = try c.decode(String.self, forKey: .patch)
            validFrom = try c.decode(Date.self, forKey: .validFrom)
            minionPool = try c.decodeIfPresent([String: Int].self, forKey: .minionPool) ?? [:]
            minionTiers = try c.decodeIfPresent([String: Int].self, forKey: .minionTiers) ?? [:]
        }
    }

    /// Which lobbies a hero is offered in (Firestone `cards_rules.json` `bgsMinionTypesRules`).
    public struct HeroTribeRule: Codable, Hashable, Sendable {
        /// Offered only when at least one of these tribes is in the lobby.
        public var needsAny: [String]
        /// Never offered when any of these tribes is in the lobby.
        public var bannedWithAny: [String]

        public init(needsAny: [String] = [], bannedWithAny: [String] = []) {
            self.needsAny = needsAny
            self.bannedWithAny = bannedWithAny
        }

        private enum CodingKeys: String, CodingKey {
            case needsAny = "needs_any"
            case bannedWithAny = "banned_with_any"
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            needsAny = try c.decodeIfPresent([String].self, forKey: .needsAny) ?? []
            bannedWithAny = try c.decodeIfPresent([String].self, forKey: .bannedWithAny) ?? []
        }
    }

    public var patch: String
    /// The client build the file was written against (informational).
    public var clientBuild: Int?
    /// When the patch went live; the newest file whose date has come applies.
    public var validFrom: Date
    /// `Race` names in rotation. Nil leaves it to the meta period.
    public var tribesInRotation: [String]?
    public var tribesPerLobby: Int?
    public var forcedTribes: [ForcedTribe]
    /// Card ID -> `IS_BACON_POOL_MINION` (1 in the pool, 0 not).
    public var minionPool: [String: Int]
    /// Card ID -> `IS_BACON_POOL_SPELL`.
    public var spellPool: [String: Int]
    /// Card IDs never sold in the shop even if flagged (Deities, tokens).
    public var nonShop: [String]
    /// Untyped minions that appear only when one of these tribes is in the lobby.
    public var minionTribeGates: [String: [String]]
    /// By the hero's base card ID (skins resolve to it).
    public var heroTribeRules: [String: HeroTribeRule]
    /// Date-gated deltas; the undated base composition retains its original values.
    public var datedCorrections: [DatedCorrection]

    public init(
        patch: String, clientBuild: Int? = nil, validFrom: Date, tribesInRotation: [String]? = nil,
        tribesPerLobby: Int? = nil, forcedTribes: [ForcedTribe] = [], minionPool: [String: Int] = [:],
        spellPool: [String: Int] = [:], nonShop: [String] = [], minionTribeGates: [String: [String]] = [:],
        heroTribeRules: [String: HeroTribeRule] = [:], datedCorrections: [DatedCorrection] = []
    ) {
        self.patch = patch
        self.clientBuild = clientBuild
        self.validFrom = validFrom
        self.tribesInRotation = tribesInRotation
        self.tribesPerLobby = tribesPerLobby
        self.forcedTribes = forcedTribes
        self.minionPool = minionPool
        self.spellPool = spellPool
        self.nonShop = nonShop
        self.minionTribeGates = minionTribeGates
        self.heroTribeRules = heroTribeRules
        self.datedCorrections = datedCorrections
    }

    // Explicit snake_case keys: a key decoding strategy would also rewrite the card IDs
    // used as dictionary keys (`BG32_172`).
    private enum CodingKeys: String, CodingKey {
        case patch
        case clientBuild = "client_build"
        case validFrom = "valid_from"
        case tribesInRotation = "tribes_in_rotation"
        case tribesPerLobby = "tribes_per_lobby"
        case forcedTribes = "forced_tribes"
        case minionPool = "minion_pool"
        case spellPool = "spell_pool"
        case nonShop = "non_shop"
        case minionTribeGates = "minion_tribe_gates"
        case heroTribeRules = "hero_tribe_rules"
        case datedCorrections = "dated_corrections"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        patch = try c.decode(String.self, forKey: .patch)
        clientBuild = try c.decodeIfPresent(Int.self, forKey: .clientBuild)
        validFrom = try c.decode(Date.self, forKey: .validFrom)
        tribesInRotation = try c.decodeIfPresent([String].self, forKey: .tribesInRotation)
        tribesPerLobby = try c.decodeIfPresent(Int.self, forKey: .tribesPerLobby)
        forcedTribes = try c.decodeIfPresent([ForcedTribe].self, forKey: .forcedTribes) ?? []
        minionPool = try c.decodeIfPresent([String: Int].self, forKey: .minionPool) ?? [:]
        spellPool = try c.decodeIfPresent([String: Int].self, forKey: .spellPool) ?? [:]
        nonShop = try c.decodeIfPresent([String].self, forKey: .nonShop) ?? []
        minionTribeGates = try c.decodeIfPresent([String: [String]].self, forKey: .minionTribeGates) ?? [:]
        heroTribeRules = try c.decodeIfPresent([String: HeroTribeRule].self, forKey: .heroTribeRules) ?? [:]
        datedCorrections = try c.decodeIfPresent([DatedCorrection].self, forKey: .datedCorrections) ?? []
    }

    /// Decodes one override file (snake_case keys, ISO 8601 dates). Unknown keys, such as
    /// the notes and sources, are ignored.
    public init(json: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self = try decoder.decode(PoolOverrides.self, from: json)
    }

    /// The override files shipped with the app.
    public static func bundled() -> [PoolOverrides] {
        HSDataResources.url("bg-pool/overrides").map(load(directory:)) ?? []
    }

    /// Every readable `*.json` override file in `directory`. Malformed files are logged and
    /// skipped; use `loadReport(directory:)` to see which.
    public static func load(directory: URL) -> [PoolOverrides] {
        loadReport(directory: directory).loaded
    }

    /// Like `load(directory:)`, but also reports the files that were skipped.
    public static func loadReport(directory: URL) -> OverrideLoad<PoolOverrides> {
        OverrideLoad.load(directory: directory) { try PoolOverrides(json: $0) }
    }

    /// `~/Library/Application Support/TavernLens/Pool/overrides`: drop a newer file here on
    /// patch day to use it before the app is rebuilt.
    public static var localDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "TavernLens/Pool/overrides", directoryHint: .isDirectory)
    }

    /// The file that applies at `date`: the newest `validFrom` not after it (a local file
    /// wins a tie), else the oldest file when none has started yet.
    public static func current(
        at date: Date = Date(), bundled: [PoolOverrides] = bundled(), local: [PoolOverrides] = load(directory: localDirectory)
    ) -> PoolOverrides? {
        var best: PoolOverrides?
        for file in bundled + local where file.validFrom <= date {
            if best.map({ file.validFrom >= $0.validFrom }) ?? true { best = file }
        }
        return best ?? (bundled + local).min { $0.validFrom < $1.validFrom }
    }
}
