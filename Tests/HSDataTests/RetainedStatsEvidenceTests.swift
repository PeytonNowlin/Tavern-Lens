import Foundation
import Testing
import HSData

@Suite("Retained source evidence")
struct RetainedStatsEvidenceTests {
    @Test("Hero turn averages retain nulls and reject invalid supplemental rows without losing the hero")
    func heroBenchmarks() throws {
        let data = Data(#"{"heroCardId":"hero","dataPoints":400,"averagePosition":4.2,"standardDeviation":2.1,"standardDeviationOfTheMean":0.1,"warbandStats":[{"turn":8,"averageStats":216},{"turn":0,"averageStats":5},{"turn":9,"averageStats":-1},{"turn":"bad","averageStats":2}],"combatWinrate":[{"turn":8,"winrate":null},{"turn":9,"winrate":54},{"turn":10,"winrate":101}]}"#.utf8)
        let hero = try JSONDecoder().decode(FirestoneHeroStat.self, from: data)
        #expect(hero.warbandStats?.map(\.turn) == [8])
        #expect(hero.combatWinrate?.count == 2 && hero.combatWinrate?.first?.winrate == nil)
        #expect(hero.standardDeviation == 2.1 && hero.standardDeviationOfTheMean == 0.1)
        #expect(try JSONDecoder().decode(FirestoneHeroStat.self, from: JSONEncoder().encode(hero)) == hero)
        let old = FirestoneHeroStat(heroCardId: "old", dataPoints: 500, averagePosition: 4)
        #expect(old.warbandStats == nil && old.combatWinrate == nil)
    }

    @Test("Trinket MMR placement preserves counts and rejects sparse or ambiguous evidence")
    func trinketBuckets() throws {
        let data = Data(#"{"trinketCardId":"trinket","dataPoints":1000,"averagePlacement":4,"pickRate":0.2,"pickRateAtMmr":[{"mmr":25,"dataPoints":200,"pickRate":0.3}],"averagePlacementAtMmr":[{"mmr":25,"dataPoints":200,"placement":3.8},{"mmr":10,"dataPoints":199,"placement":2.8}]}"#.utf8)
        var row = try JSONDecoder().decode(TrinketStats.Entry.self, from: data)
        #expect(row.pickRate == 0.2 && row.pickRateAtMmr?.first?.pickRate == 0.3)
        #expect(row.placement(atMMRPercentile: 25)?.dataPoints == 200 && row.placement(atMMRPercentile: 10) == nil)
        #expect(row.pickRateAtMmr?.first?.dataPoints == 200)
        let duplicate = try #require(row.averagePlacementAtMmr?.first)
        row.averagePlacementAtMmr?.append(duplicate)
        #expect(row.placement(atMMRPercentile: 25) == nil)
        #expect(try JSONDecoder().decode(TrinketStats.Entry.self, from: JSONEncoder().encode(row)) == row)
        let legacy = try JSONDecoder().decode(TrinketStats.Entry.self,
            from: Data(#"{"trinketCardId":"old","dataPoints":400,"averagePlacement":4}"#.utf8))
        #expect(legacy.pickRate == nil && legacy.averagePlacementAtMmr == nil)
    }
}
