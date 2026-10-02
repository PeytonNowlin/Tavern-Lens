import Foundation
import HSData
import Testing

@Suite("MMR percentile evidence")
struct MMRPercentileTests {
    static let now = Date(timeIntervalSince1970: 1_791_000_000)
    static let rows: [MMRPercentileRow] = [
        .init(percentile: 100, mmr: 0), .init(percentile: 50, mmr: 6000),
        .init(percentile: 25, mmr: 6600), .init(percentile: 10, mmr: 7200), .init(percentile: 1, mmr: 9300),
    ]

    static func table(
        _ rows: [MMRPercentileRow] = rows, window: HeroStatsWindow = .pastThree,
        updatedAt: Date = now, fetchedAt: Date = now, sourceURL: String? = nil
    ) -> MMRPercentileTable? {
        MMRPercentileTable(rows: rows, window: window,
            sourceURL: sourceURL ?? FirestoneHeroStatsSource.percentilesURL(window: window).absoluteString,
            updatedAt: updatedAt, fetchedAt: fetchedAt)
    }

    @Test("Rating boundaries use actual feed cutoffs, including raw top one percent")
    func boundaries() throws {
        let table = try #require(Self.table())
        for (rating, bucket) in [(0, 100), (5999, 100), (6000, 50), (6599, 50), (6600, 25),
                                (7199, 25), (7200, 10), (9299, 10), (9300, 1), (12_000, 1)] {
            #expect(table.bucket(for: rating) == bucket)
        }
        #expect(table.bucket(for: -1) == nil)
        #expect(Self.table(Array(Self.rows.reversed()))?.bucket(for: 6600) == 25)
    }

    @Test("A complete unambiguous five-bucket table and its exact same-window public source are required")
    func invalidTables() {
        #expect(Self.table(Array(Self.rows.dropLast())) == nil)
        #expect(Self.table(Self.rows + [Self.rows[1]]) == nil)
        #expect(Self.table([.init(percentile: 100, mmr: 0), .init(percentile: 50, mmr: 6000),
                           .init(percentile: 25, mmr: 5999), .init(percentile: 10, mmr: 7200),
                           .init(percentile: 1, mmr: 9300)]) == nil)
        #expect(Self.table([.init(percentile: 100, mmr: -1)] + Self.rows.dropFirst()) == nil)
        #expect(Self.table(sourceURL: "https://example.com/mmr-percentiles.gz.json") == nil)
        #expect(Self.table(sourceURL: FirestoneHeroStatsSource.percentilesURL(window: .pastSeven).absoluteString) == nil)
        #expect(Self.table(sourceURL: "https://static.zerotoheroes.com/api/bgs/duo/hero-stats/past-three/mmr-percentiles.gz.json") == nil)
        #expect(Self.table(sourceURL: FirestoneHeroStatsSource.url(window: .pastThree, mmrPercentile: 25).absoluteString) != nil)
    }

    @Test("Future dates and old publication dates cannot be made fresh by receiving the file again")
    func freshness() throws {
        #expect(try #require(Self.table()).isFresh(at: Self.now))
        #expect(try #require(Self.table(updatedAt: Self.now.addingTimeInterval(-24 * 3600))).isFresh(at: Self.now))
        #expect(!(try #require(Self.table(updatedAt: Self.now.addingTimeInterval(-24 * 3600 - 1)))).isFresh(at: Self.now))
        #expect(!(try #require(Self.table(updatedAt: Self.now.addingTimeInterval(1)))).isFresh(at: Self.now))
        #expect(!(try #require(Self.table(fetchedAt: Self.now.addingTimeInterval(1)))).isFresh(at: Self.now))
        #expect(Self.table(updatedAt: Date(timeIntervalSince1970: .nan)) == nil)
        #expect(HeroStatsRating(rating: 6600, source: .manual, recordedAt: Self.now).isRecent(at: Self.now))
        #expect(HeroStatsRating(rating: 6600, source: .screen, recordedAt: Self.now.addingTimeInterval(-24 * 3600)).isRecent(at: Self.now))
        #expect(!HeroStatsRating(rating: 6600, source: .screen, recordedAt: Self.now.addingTimeInterval(-24 * 3600 - 1)).isRecent(at: Self.now))
        #expect(!HeroStatsRating(rating: 6600, source: .manual, recordedAt: Self.now.addingTimeInterval(1)).isRecent(at: Self.now))
        #expect(!HeroStatsRating(rating: -1, source: .manual, recordedAt: Self.now).isRecent(at: Self.now))
    }

    @Test("Malformed supplemental cutoffs leave hero rows usable and older encodings have no new key")
    func embeddedDecoding() throws {
        let old = FirestoneHeroStatsFile(lastUpdateDate: Self.now, dataPoints: 100,
            heroStats: [.init(heroCardId: "BG_H", dataPoints: 100, averagePosition: 4)])
        let encoded = try JSONEncoder().encode(old)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("mmrPercentiles"))
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["mmrPercentiles"] = [["percentile": "broken", "mmr": 6000]]
        let malformed = try FirestoneHeroStatsFile(json: JSONSerialization.data(withJSONObject: object))
        #expect(malformed.heroStats.count == 1)
        #expect(malformed.mmrPercentiles == nil)
        object["mmrPercentiles"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Self.rows))
        let valid = try FirestoneHeroStatsFile(json: JSONSerialization.data(withJSONObject: object))
        #expect(valid.mmrPercentiles == Self.rows)
        #expect(try FirestoneHeroStatsFile(json: JSONEncoder().encode(valid)) == valid)
    }
}
