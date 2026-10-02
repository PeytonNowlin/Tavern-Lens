import Foundation
import TavernEngine
import Testing

@Suite("Hero population archive")
struct HeroStatsMMRViewTests {
    @Test("Default hero stats keep the old JSON shape and old archives decode without provenance")
    func legacyEncoding() throws {
        let old = Data(#"{"averagePlacement":4,"baseAveragePlacement":4,"tribeModifier":0,"tier":"B","top4Percent":50,"winPercent":10,"placements":[10,15,15,10,10,15,15,10],"dataPoints":1000,"window":"past-three"}"#.utf8)
        let view = try JSONDecoder().decode(HeroPickStatsView.self, from: old)
        #expect(view.population == nil)
        let encoded = try JSONEncoder().encode(view)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["population"] == nil)
        #expect(try JSONDecoder().decode(HeroPickStatsView.self, from: encoded) == view)
    }

    @Test("Each offered hero archives the population of its selected window, even when windows use different buckets")
    func mixedWindowProvenance() throws {
        let now = HeroPickSyntheticTests.updatedAt
        let rating = HeroStatsRating(rating: 6600, source: .manual, recordedAt: now)
        let rows: [MMRPercentileRow] = [.init(percentile: 100, mmr: 0), .init(percentile: 50, mmr: 6000),
            .init(percentile: 25, mmr: 6600), .init(percentile: 10, mmr: 7200), .init(percentile: 1, mmr: 9300)]
        func selection(_ window: HeroStatsWindow, _ bucket: Int) throws -> HeroStatsMMRSelection {
            var cutoffs = rows
            if window == .pastSeven { cutoffs[2] = .init(percentile: 25, mmr: 6700) }
            let table = try #require(MMRPercentileTable(rows: cutoffs, window: window,
                sourceURL: FirestoneHeroStatsSource.url(window: window, mmrPercentile: 100).absoluteString,
                updatedAt: now, fetchedAt: now))
            return .init(window: window, mmrPercentile: bucket, matchedPercentile: bucket, rating: rating,
                table: table, statsUpdatedAt: now, fetchedAt: now, reason: .mapped)
        }
        let three = try selection(.pastThree, 25)
        let seven = try selection(.pastSeven, 50)
        let base = HeroPickSyntheticTests.set([
            .pastThree: [HeroPickSyntheticTests.stat("BG_A", games: 400), HeroPickSyntheticTests.stat("BG_B", games: 100)],
            .pastSeven: [HeroPickSyntheticTests.stat("BG_B", games: 400)],
        ])
        let stats = HeroStatsSet(mmrPercentile: 25, files: base.files, selections: [.pastThree: three, .pastSeven: seven])
        let engine = try HeroPickSyntheticTests.engine(HeroPickSyntheticTests.pickScreen(["BG_A", "BG_B"]), stats: stats)
        let pick = try #require(engine.state.game?.heroPick)
        #expect(pick.offers[0].stats?.population == three)
        #expect(pick.offers[1].stats?.population == seven)
        #expect(pick.offers[1].stats?.population?.table?.bucket(for: rating.rating) == 50)
        #expect(pick.offers[1].stats?.population?.statsSourceURL.contains("/mmr-50/past-seven/") == true)
        #expect(try JSONDecoder().decode(HeroPickView.self, from: JSONEncoder().encode(pick)) == pick)
    }
}
