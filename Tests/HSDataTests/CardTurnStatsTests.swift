import Foundation
import HSData
import Testing

@Suite("Card performance by turn")
struct CardTurnStatsTests {
    static let now = ISO8601DateFormatter().date(from: "2026-10-02T13:00:00Z")!
    static let raw = Data("""
    {"lastUpdateDate":"2026-10-02T12:00:00.000Z","dataPoints":1000,"timePeriod":"last-patch",
     "cardStats":[{"cardId":"BG_TEST","totalPlayed":500,"averagePlacement":3.5,"averagePlacementOther":4.25,
       "turnStats":[{"turn":8,"totalPlayed":200,"totalOther":600,"averagePlacement":3.5,"averagePlacementOther":4.25}]}]}
    """.utf8)
    static let incompleteRaw = Data("""
    {"lastUpdateDate":"2026-10-02T12:00:00Z","dataPoints":1000,"timePeriod":"last-patch",
     "cardStats":[{"cardId":"BG_TEST","totalPlayed":500,"averagePlacement":3.5,"averagePlacementOther":4.25,
      "turnStats":[
       {"turn":8,"totalPlayed":200,"totalOther":600,"averagePlacement":3.5,"averagePlacementOther":4.25},
       {"turn":9,"totalPlayed":4,"totalOther":0,"averagePlacement":3.0,"averagePlacementOther":null}]}]}
    """.utf8)

    @Test("Exact-turn evidence preserves both populations and a lower-is-better association")
    func exactTurn() throws {
        let stats = try CardTurnStats(json: Self.raw)
        let entry = try #require(stats.entry(cardID: "BG_TEST", turn: 8, now: Self.now))
        #expect(entry.totalPlayed == 200)
        #expect(entry.totalOther == 600)
        #expect(entry.impact == -0.75)
        #expect(stats.entry(cardID: "BG_TEST", turn: 9, now: Self.now) == nil)
        #expect(stats.entry(cardID: "BG_MISSING", turn: 8, now: Self.now) == nil)
    }

    @Test("Null and missing turn values never substitute for an exact turn")
    func missingTurns() throws {
        for replacement in ["\"turn\":null,", ""] {
            let raw = String(decoding: Self.raw, as: UTF8.self).replacingOccurrences(of: "\"turn\":8,", with: replacement)
            let stats = try CardTurnStats(json: Data(raw.utf8))
            #expect(stats.entry(cardID: "BG_TEST", turn: 8, now: Self.now) == nil)
        }
    }

    @Test("Null comparator averages invalidate one row rather than the entire source")
    func incompleteComparison() throws {
        let stats = try CardTurnStats(json: Self.incompleteRaw)
        #expect(stats.entry(cardID: "BG_TEST", turn: 8, now: Self.now)?.impact == -0.75)
        #expect(stats.entry(cardID: "BG_TEST", turn: 9, now: Self.now) == nil)
        var invalid = stats
        invalid.cardStats[0].turnStats[0].averagePlacement = nil
        #expect(invalid.entry(cardID: "BG_TEST", turn: 8, now: Self.now) == nil)
    }

    @Test("Both comparison groups must meet the sample floor")
    func populations() throws {
        for (played, other) in [(199, 600), (200, 199), (-1, 600), (200, -1), (0, 0)] {
            var stats = try CardTurnStats(json: Self.raw)
            stats.cardStats[0].turnStats[0].totalPlayed = played
            stats.cardStats[0].turnStats[0].totalOther = other
            #expect(stats.entry(cardID: "BG_TEST", turn: 8, now: Self.now) == nil)
        }
        var sparse = try CardTurnStats(json: Self.raw)
        sparse.cardStats[0].turnStats[0].totalPlayed = 100
        sparse.cardStats[0].turnStats[0].totalOther = 100
        #expect(sparse.entry(cardID: "BG_TEST", turn: 8, now: Self.now, minimumPopulation: 100) != nil)
        sparse.cardStats[0].turnStats[0].totalPlayed = 0
        #expect(sparse.entry(cardID: "BG_TEST", turn: 8, now: Self.now, minimumPopulation: 0) == nil)
    }

    @Test("Invalid placement numbers never reach the advisor", arguments: [Double.nan, .infinity, -.infinity, 0.99, 8.01])
    func placements(invalid: Double) throws {
        var stats = try CardTurnStats(json: Self.raw)
        stats.cardStats[0].turnStats[0].averagePlacement = invalid
        #expect(stats.entry(cardID: "BG_TEST", turn: 8, now: Self.now) == nil)
        stats.cardStats[0].turnStats[0].averagePlacement = 3.5
        stats.cardStats[0].turnStats[0].averagePlacementOther = invalid
        #expect(stats.entry(cardID: "BG_TEST", turn: 8, now: Self.now) == nil)
    }

    @Test("Source generation time and scope govern freshness")
    func freshnessAndScope() throws {
        let stats = try CardTurnStats(json: Self.raw)
        let generated = try #require(stats.updatedAt)
        #expect(stats.entry(cardID: "BG_TEST", turn: 8, now: generated.addingTimeInterval(48 * 3600)) != nil)
        #expect(stats.entry(cardID: "BG_TEST", turn: 8, now: generated.addingTimeInterval(48 * 3600 + 1)) == nil)
        #expect(stats.entry(cardID: "BG_TEST", turn: 8, now: generated.addingTimeInterval(-1)) == nil)
        var invalid = stats
        invalid.lastUpdateDate = "not a date"
        #expect(invalid.entry(cardID: "BG_TEST", turn: 8, now: Self.now) == nil)
        invalid = stats
        invalid.timePeriod = "all-time"
        #expect(invalid.entry(cardID: "BG_TEST", turn: 8, now: Self.now) == nil)
        invalid = stats
        invalid.mmrPercentile = 100
        #expect(invalid.entry(cardID: "BG_TEST", turn: 8, now: Self.now) == nil)
        invalid = stats
        invalid.dataPoints = -1
        #expect(invalid.entry(cardID: "BG_TEST", turn: 8, now: Self.now) == nil)
        invalid = stats
        invalid.sourceURL = "https://example.com/unverified.json"
        #expect(invalid.entry(cardID: "BG_TEST", turn: 8, now: Self.now) == nil)
    }

    @Test("Duplicate card-turn evidence is ambiguous, even when repeated values agree")
    func duplicates() throws {
        var stats = try CardTurnStats(json: Self.raw)
        stats.cardStats[0].turnStats.append(stats.cardStats[0].turnStats[0])
        #expect(stats.entry(cardID: "BG_TEST", turn: 8, now: Self.now) == nil)
        stats = try CardTurnStats(json: Self.raw)
        stats.cardStats.append(stats.cardStats[0])
        #expect(stats.entry(cardID: "BG_TEST", turn: 8, now: Self.now) == nil)
    }

    @Test("Archived request subsets are deterministic and retain their source identity")
    func subset() throws {
        var stats = try CardTurnStats(json: Self.raw)
        var another = stats.cardStats[0]
        another.cardId = "BG_A"
        stats.cardStats.append(another)
        var later = stats.cardStats[0].turnStats[0]
        later.turn = 9
        stats.cardStats[0].turnStats.append(later)
        let archived = stats.subset(cardIDs: ["BG_TEST", "BG_A", "BG_MISSING"], turn: 8, now: Self.now)
        #expect(archived.cardStats.map(\.cardId) == ["BG_A", "BG_TEST"])
        #expect(archived.cardStats.allSatisfy { $0.turnStats.count == 1 && $0.turnStats[0].turn == 8 })
        #expect(archived.lastUpdateDate == "2026-10-02T12:00:00.000Z")
        #expect(archived.timePeriod == "last-patch")
        #expect(archived.mmrPercentile == 25)
        #expect(archived.sourceURL == "https://static.zerotoheroes.com/api/bgs/card-stats/mmr-25/last-patch/overview-from-hourly.gz.json")
        #expect(try JSONDecoder().decode(CardTurnStats.self, from: JSONEncoder().encode(archived)) == archived)
    }
}
