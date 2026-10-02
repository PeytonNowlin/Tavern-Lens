import Foundation

/// A rating observed from the player's own lobby or entered manually. No opponent rating is inferred.
public struct HeroStatsRating: Codable, Hashable, Sendable {
    public enum Source: String, Codable, Hashable, Sendable { case manual, screen }
    public let rating: Int
    public let source: Source
    public let recordedAt: Date
    public static let recentFor: TimeInterval = 24 * 60 * 60

    public init(rating: Int, source: Source, recordedAt: Date) {
        self.rating = rating
        self.source = source
        self.recordedAt = recordedAt
    }

    public func isRecent(at now: Date) -> Bool {
        let age = now.timeIntervalSince(recordedAt)
        return rating >= 0 && recordedAt.timeIntervalSince1970.isFinite && age.isFinite && age >= 0 && age <= Self.recentFor
    }
}

public struct MMRPercentileRow: Codable, Hashable, Sendable {
    public let percentile: Int
    public let mmr: Int

    public init(percentile: Int, mmr: Int) {
        self.percentile = percentile
        self.mmr = mmr
    }
}

/// Firestone's five cutoffs, tied to the exact solo window and publication that supplied them.
public struct MMRPercentileTable: Codable, Hashable, Sendable {
    public static let buckets = [100, 50, 25, 10, 1]
    public static let freshFor: TimeInterval = 24 * 60 * 60
    public let rows: [MMRPercentileRow]
    public let window: HeroStatsWindow
    public let sourceURL: String
    /// Embedded file's `lastUpdateDate`, or the standalone feed's HTTP Last-Modified.
    public let updatedAt: Date
    /// Receipt/conditional confirmation time; never substitutes for publication time.
    public let fetchedAt: Date

    public init?(rows: [MMRPercentileRow], window: HeroStatsWindow, sourceURL: String, updatedAt: Date, fetchedAt: Date) {
        guard rows.count == Self.buckets.count, Set(rows.map(\.percentile)) == Set(Self.buckets),
              updatedAt.timeIntervalSince1970.isFinite, fetchedAt.timeIntervalSince1970.isFinite
        else { return nil }
        let ordered = Self.buckets.compactMap { bucket in rows.first { $0.percentile == bucket } }
        guard ordered.first?.mmr == 0, ordered.allSatisfy({ $0.mmr >= 0 }),
              zip(ordered, ordered.dropFirst()).allSatisfy({ pair in pair.0.mmr < pair.1.mmr })
        else { return nil }
        let allowedURLs = [FirestoneHeroStatsSource.percentilesURL(window: window).absoluteString]
            + Self.buckets.map { FirestoneHeroStatsSource.url(window: window, mmrPercentile: $0).absoluteString }
        guard allowedURLs.contains(sourceURL) else { return nil }
        self.rows = ordered
        self.window = window
        self.sourceURL = sourceURL
        self.updatedAt = updatedAt
        self.fetchedAt = fetchedAt
    }

    /// Raw mapping: the highest rating cutoff reached, including percentile 1.
    public func bucket(for rating: Int) -> Int? {
        guard rating >= 0 else { return nil }
        return rows.last { $0.mmr <= rating }?.percentile
    }

    public func isFresh(at now: Date) -> Bool {
        let publishedAge = now.timeIntervalSince(updatedAt)
        let receivedAge = now.timeIntervalSince(fetchedAt)
        return publishedAge.isFinite && receivedAge.isFinite && publishedAge >= 0 && publishedAge <= Self.freshFor
            && receivedAge >= 0 && updatedAt <= fetchedAt
    }

    private enum CodingKeys: String, CodingKey { case rows, window, sourceURL, updatedAt, fetchedAt }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let table = try Self(
            rows: c.decode([MMRPercentileRow].self, forKey: .rows), window: c.decode(HeroStatsWindow.self, forKey: .window),
            sourceURL: c.decode(String.self, forKey: .sourceURL), updatedAt: c.decode(Date.self, forKey: .updatedAt),
            fetchedAt: c.decode(Date.self, forKey: .fetchedAt)
        ) else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid MMR percentile evidence")) }
        self = table
    }
}

/// Why this window's hero population was selected, retained with the numbers shown.
public struct HeroStatsMMRSelection: Codable, Hashable, Sendable {
    public enum Reason: String, Codable, Hashable, Sendable {
        case mapped, topOneBroadened, noRecentRating, noFreshTable, bucketUnavailable
    }
    public let window: HeroStatsWindow
    public let mmrPercentile: Int
    public let matchedPercentile: Int?
    public let rating: HeroStatsRating?
    public let table: MMRPercentileTable?
    public let statsSourceURL: String
    public let statsUpdatedAt: Date?
    public let fetchedAt: Date
    public let reason: Reason

    public init(
        window: HeroStatsWindow, mmrPercentile: Int, matchedPercentile: Int? = nil, rating: HeroStatsRating?,
        table: MMRPercentileTable?, statsUpdatedAt: Date?, fetchedAt: Date, reason: Reason
    ) {
        self.window = window
        self.mmrPercentile = mmrPercentile
        self.matchedPercentile = matchedPercentile
        self.rating = rating
        self.table = table
        statsSourceURL = FirestoneHeroStatsSource.url(window: window, mmrPercentile: mmrPercentile).absoluteString
        self.statsUpdatedAt = statsUpdatedAt
        self.fetchedAt = fetchedAt
        self.reason = reason
    }
}

public enum MMRPercentileResponse: Hashable, Sendable {
    case notModified
    case body(Data, etag: String?, lastModified: Date?)
}

public protocol MMRPercentileSource: Sendable {
    func fetchPercentiles(window: HeroStatsWindow, etag: String?) async throws -> MMRPercentileResponse
}
