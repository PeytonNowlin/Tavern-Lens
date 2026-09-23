import Foundation

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

    public init(
        patch: String, clientBuild: Int? = nil, validFrom: Date, tribesInRotation: [String]? = nil,
        tribesPerLobby: Int? = nil, forcedTribes: [ForcedTribe] = [], minionPool: [String: Int] = [:],
        spellPool: [String: Int] = [:], nonShop: [String] = [], minionTribeGates: [String: [String]] = [:],
        heroTribeRules: [String: HeroTribeRule] = [:]
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

    /// Every readable `*.json` override file in `directory`.
    public static func load(directory: URL) -> [PoolOverrides] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? PoolOverrides(json: Data(contentsOf: $0)) }
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
