import Foundation

/// A time window of Firestone's hero stats (the URL slug).
public enum HeroStatsWindow: String, CaseIterable, Codable, Hashable, Sendable {
    /// Mostly the current meta.
    case pastThree = "past-three"
    case pastSeven = "past-seven"
    /// Since the last Battlegrounds patch Firestone knows of (it can span a few patches).
    case lastPatch = "last-patch"

    /// The order heroes are looked up in: the newest window with enough games wins.
    public static let preference: [HeroStatsWindow] = [.pastThree, .pastSeven, .lastPatch]
}

/// One of Firestone's hero-stats files
/// (`static.zerotoheroes.com/api/bgs/hero-stats/mmr-<P>/<window>/overview-from-hourly.gz.json`,
/// docs/research/hero-pick-stats.md §2.3). Only the fields the hero pick reads are kept, and
/// decoding is lenient: the files are undocumented, so a hero row that doesn't decode is
/// skipped rather than failing the file.
public struct FirestoneHeroStatsFile: Codable, Hashable, Sendable {
    /// When Firestone rebuilt the file (about every 3 h).
    public var lastUpdateDate: Date?
    /// Games in the file.
    public var dataPoints: Int
    public var heroStats: [FirestoneHeroStat]

    public init(lastUpdateDate: Date?, dataPoints: Int, heroStats: [FirestoneHeroStat]) {
        self.lastUpdateDate = lastUpdateDate
        self.dataPoints = dataPoints
        self.heroStats = heroStats
    }

    public init(json: Data) throws {
        self = try JSONDecoder().decode(FirestoneHeroStatsFile.self, from: json)
    }

    private enum CodingKeys: String, CodingKey {
        case lastUpdateDate, dataPoints, heroStats
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastUpdateDate = try c.decodeIfPresent(String.self, forKey: .lastUpdateDate).flatMap(FirestoneDate.parse)
        dataPoints = try c.decodeIfPresent(Int.self, forKey: .dataPoints) ?? 0
        heroStats = try c.decode([Lenient<FirestoneHeroStat>].self, forKey: .heroStats).compactMap(\.value)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(lastUpdateDate.map(FirestoneDate.format), forKey: .lastUpdateDate)
        try c.encode(dataPoints, forKey: .dataPoints)
        try c.encode(heroStats, forKey: .heroStats)
    }

    /// A file worth keeping: Firestone sometimes publishes an empty or partial one.
    public var isUsable: Bool { dataPoints > 0 && heroStats.count >= 50 }
}

/// One hero's row in a Firestone hero-stats file.
public struct FirestoneHeroStat: Codable, Hashable, Sendable {
    public struct Placement: Codable, Hashable, Sendable {
        public var rank: Int
        /// Percent of the hero's games (0…100).
        public var percentage: Double

        public init(rank: Int, percentage: Double) {
            self.rank = rank
            self.percentage = percentage
        }
    }

    /// The hero's placement in games with one tribe in the lobby, against its overall average.
    public struct TribeStat: Codable, Hashable, Sendable {
        /// Firestone's `Race` number, the same as the game's `CARDRACE` (Undead 11, Mech 17, …).
        public var tribe: Int
        /// Games with the tribe in the lobby.
        public var dataPoints: Int
        /// Games without it.
        public var dataPointsOnMissingTribe: Int
        /// Average placement with the tribe minus the hero's overall average (negative is better).
        public var impactAveragePosition: Double

        public init(tribe: Int, dataPoints: Int, dataPointsOnMissingTribe: Int, impactAveragePosition: Double) {
            self.tribe = tribe
            self.dataPoints = dataPoints
            self.dataPointsOnMissingTribe = dataPointsOnMissingTribe
            self.impactAveragePosition = impactAveragePosition
        }
    }

    /// Always a base hero's card ID (skins are folded into it).
    public var heroCardId: String
    /// Games played with the hero.
    public var dataPoints: Int
    public var totalOffered: Int?
    public var totalPicked: Int?
    public var averagePosition: Double
    public var conservativePositionEstimate: Double?
    public var placementDistribution: [Placement]
    public var tribeStats: [TribeStat]

    public init(
        heroCardId: String, dataPoints: Int, totalOffered: Int? = nil, totalPicked: Int? = nil,
        averagePosition: Double, conservativePositionEstimate: Double? = nil, placementDistribution: [Placement] = [],
        tribeStats: [TribeStat] = []
    ) {
        self.heroCardId = heroCardId
        self.dataPoints = dataPoints
        self.totalOffered = totalOffered
        self.totalPicked = totalPicked
        self.averagePosition = averagePosition
        self.conservativePositionEstimate = conservativePositionEstimate
        self.placementDistribution = placementDistribution
        self.tribeStats = tribeStats
    }

    private enum CodingKeys: String, CodingKey {
        case heroCardId, dataPoints, totalOffered, totalPicked, averagePosition, conservativePositionEstimate
        case placementDistribution, tribeStats
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        heroCardId = try c.decode(String.self, forKey: .heroCardId)
        dataPoints = try c.decode(Int.self, forKey: .dataPoints)
        totalOffered = try c.decodeIfPresent(Int.self, forKey: .totalOffered)
        totalPicked = try c.decodeIfPresent(Int.self, forKey: .totalPicked)
        averagePosition = try c.decode(Double.self, forKey: .averagePosition)
        conservativePositionEstimate = try c.decodeIfPresent(Double.self, forKey: .conservativePositionEstimate)
        placementDistribution = try c.decodeIfPresent([Lenient<Placement>].self, forKey: .placementDistribution)?
            .compactMap(\.value) ?? []
        tribeStats = try c.decodeIfPresent([Lenient<TribeStat>].self, forKey: .tribeStats)?.compactMap(\.value) ?? []
    }

    /// Percent of games in 1st place.
    public var winPercent: Double { placementDistribution.filter { $0.rank == 1 }.map(\.percentage).reduce(0, +) }

    /// Percent of games in the top 4.
    public var top4Percent: Double { placementDistribution.filter { $0.rank <= 4 }.map(\.percentage).reduce(0, +) }

    /// Percent of games in each place, 1st to 8th (0 where the file has no row).
    public var placements: [Double] {
        (1...8).map { rank in placementDistribution.filter { $0.rank == rank }.map(\.percentage).reduce(0, +) }
    }

    /// How often the hero is picked when offered.
    public var pickRate: Double? {
        guard let totalOffered, let totalPicked, totalOffered > 0 else { return nil }
        return Double(totalPicked) / Double(totalOffered)
    }
}

/// Firestone's hero stats for one MMR bucket, one file per window.
public struct HeroStatsSet: Hashable, Sendable {
    /// Firestone's MMR percentile bucket: 100 is all players.
    public let mmrPercentile: Int
    public let files: [HeroStatsWindow: FirestoneHeroStatsFile]
    /// A hero needs this many games in a window for the window to be used for it.
    public let minimumGames: Int

    public init(mmrPercentile: Int = 100, files: [HeroStatsWindow: FirestoneHeroStatsFile], minimumGames: Int = 300) {
        self.mmrPercentile = mmrPercentile
        self.files = files
        self.minimumGames = minimumGames
        index = files.mapValues { file in
            Dictionary(file.heroStats.map { ($0.heroCardId, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    private let index: [HeroStatsWindow: [String: FirestoneHeroStat]]

    /// Every hero in any window.
    public var heroCardIDs: Set<String> { Set(index.values.flatMap(\.keys)) }

    /// A base hero's stats from the newest window where it has at least `minimumGames`
    /// games (past three days, then past seven, then last patch); failing that, the window
    /// where it has the most games.
    public func stat(for heroCardID: String) -> (stat: FirestoneHeroStat, window: HeroStatsWindow)? {
        var best: (stat: FirestoneHeroStat, window: HeroStatsWindow)?
        for window in HeroStatsWindow.preference {
            guard let stat = index[window]?[heroCardID] else { continue }
            if stat.dataPoints >= minimumGames { return (stat, window) }
            if stat.dataPoints > (best?.stat.dataPoints ?? -1) { best = (stat, window) }
        }
        return best
    }

    /// When a window's file was rebuilt.
    public func lastUpdate(of window: HeroStatsWindow) -> Date? { files[window]?.lastUpdateDate }

    /// Older than 24 hours at `now`: show a stale badge.
    public static let staleAfter: TimeInterval = 24 * 60 * 60

    public static func isStale(updatedAt: Date?, now: Date) -> Bool {
        guard let updatedAt else { return true }
        return now.timeIntervalSince(updatedAt) > staleAfter
    }
}

/// Firestone's ISO 8601 dates (`2026-09-23T00:10:26.557Z`), with or without the fraction.
enum FirestoneDate {
    static func parse(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)) {
            return date
        }
        return try? Date(text, strategy: .iso8601)
    }

    static func format(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))
    }
}

/// Decodes a value, or nil where it doesn't decode.
struct Lenient<Value: Decodable>: Decodable {
    var value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
