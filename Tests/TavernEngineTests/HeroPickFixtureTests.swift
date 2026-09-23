import Foundation
import HSLog
import Testing
import TavernEngine

/// Seam 1 on the captured games: the hero pick joined with the committed Firestone stats
/// fixture. Skipped when the private fixture logs are absent.
@Suite("Hero pick stats on captured games")
struct HeroPickFixtureTests {
    /// The offer, left to right, as the choice lists it (the final hand order).
    static let offered = ["BG35_HERO_001", "TB_BaconShop_HERO_15", "BG23_HERO_305", "BG20_HERO_283"]
    static let lobby = ["ABERRATION", "DRAGON", "ELEMENTAL", "QUILBOAR", "UNDEAD"]

    /// Replays the full game with hero stats, card data and the pool; with `readBanner`, the
    /// lobby's tribes are read from the screen as soon as the hero pick shows.
    static func replay(readBanner: Bool) throws -> [TimelineEntry] {
        let url = try #require(Fixtures.url(Fixtures.fullGame))
        let session = LogSession(directory: url.deletingLastPathComponent())
        var engine = TavernEngine(cards: PoolFixture.cards, pool: PoolFixture.pool, session: session)
        engine.useHeroStats(HeroStatsFixture.stats)
        var read = !readBanner
        try LogFileReader.forEachLine(in: url) { line in
            engine.ingest(line)
            if !read, engine.state.game?.heroPick != nil {
                engine.ingestScreenTribes(ScreenTribeReading(tribes: lobby.map { HS.Race(name: $0)! }))
                read = true
            }
        }
        engine.finish()
        return engine.timeline
    }

    @Test(
        "All four offered heroes resolve to stats entries, in screen order, until the first recruit phase",
        .enabled(if: Fixtures.isAvailable(Fixtures.fullGame), "private fixture log not present")
    )
    func offerJoins() throws {
        let timeline = try Self.replay(readBanner: false)
        let picks = timeline.compactMap { $0.state.game?.heroPick }
        let first = try #require(picks.first)
        #expect(first.offers.map(\.cardID) == Self.offered)
        #expect(first.offers.map(\.baseCardID) == Self.offered)
        #expect(first.offers.map(\.name) == ["Genn, Worgen King", "George the Fallen", "Heistbaron Togwaggle", "Galewing"])
        #expect(first.offers.allSatisfy { $0.stats != nil })
        #expect(first.offers.allSatisfy { $0.stats?.window == .pastThree })
        // Unadjusted Firestone numbers (past three days, all players).
        #expect(first.offers.map { $0.stats?.baseAveragePlacement } == [4.21, 3.92, 4.17, 3.85])
        #expect(first.offers.map { $0.stats?.dataPoints } == [2877, 1464, 825, 1168])
        // Two of the four are locked (no Tavern Pass): the outer ones.
        #expect(first.offers.map(\.isLocked) == [true, false, false, true])
        #expect(first.tribeAdjustment == .estimated)
        #expect(first.statsUpdatedAt == "2026-09-23T00:10:26Z")
        #expect(!first.isStale)  // the game started about an hour after the rebuild

        // Every hero-pick entry shows the same four; the pick is George, and from the first
        // recruit phase on the hero pick is gone.
        #expect(picks.allSatisfy { $0.offers.map(\.cardID) == Self.offered })
        #expect(picks.last?.chosenCardID == "TB_BaconShop_HERO_15")
        let pickEntries = timeline.filter { $0.state.game?.heroPick != nil }
        #expect(pickEntries.allSatisfy { $0.state.game?.phase == .heroPick })
        let firstRecruit = try #require(timeline.firstIndex { $0.state.game?.phase == .recruit })
        #expect(timeline[firstRecruit...].allSatisfy { $0.state.game?.heroPick == nil })
    }

    @Test(
        "With the lobby's tribes known, averages and tiers match Firestone's algorithm without the forced Aberration",
        .enabled(if: Fixtures.isAvailable(Fixtures.fullGame), "private fixture log not present")
    )
    func tribeAdjusted() throws {
        let timeline = try Self.replay(readBanner: true)
        let pick = try #require(timeline.compactMap { $0.state.game?.heroPick }.first { $0.tribeAdjustment == .exact })
        // docs/research/validation-scripts/herostats/expected_pick.py on the same fixture.
        #expect(pick.offers.map { $0.stats?.tribeModifier } == [-0.10, -0.18, -0.06, 0.06])
        #expect(pick.offers.map { $0.stats?.averagePlacement } == [4.11, 3.74, 4.11, 3.91])
        #expect(pick.offers.map { $0.stats?.tier } == [.C, .B, .C, .B])
        #expect(pick.offers.map { $0.stats?.top4Percent } == [53.8, 60.8, 56.5, 61.9])
        #expect(pick.offers.map { $0.stats?.winPercent } == [17.3, 16.8, 12.4, 19.0])
    }

    @Test(
        "Every captured game's offer joins the stats, and the picked hero is one of the offered",
        .enabled(if: [Fixtures.truncatedGame, TribeFixtureTests.stressGame, Fixtures.abandonedGame].allSatisfy(Fixtures.isAvailable),
                 "private fixture logs not present"),
        arguments: [Fixtures.truncatedGame, TribeFixtureTests.stressGame, Fixtures.abandonedGame]
    )
    func otherGamesJoin(_ log: String) throws {
        let url = try #require(Fixtures.url(log))
        var engine = TavernEngine(cards: PoolFixture.cards)
        engine.useHeroStats(HeroStatsFixture.stats)
        try LogFileReader.forEachLine(in: url) { engine.ingest($0) }
        engine.finish()
        let picks = engine.timeline.compactMap { $0.state.game?.heroPick }
        let first = try #require(picks.first)
        #expect(first.offers.count >= 2)
        #expect(first.offers.allSatisfy { $0.stats != nil }, "no stats for \(first.offers.filter { $0.stats == nil }.map(\.cardID))")
        let chosen = try #require(picks.last?.chosenCardID)
        #expect(first.offers.map(\.cardID).contains(chosen))
        let hero = engine.timeline.last { $0.state.game?.localHeroCardID != nil }?.state.game?.localHeroCardID
        #expect(hero == chosen)
    }
}
