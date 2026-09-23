import Foundation
import HSLog
import Testing
import TavernEngine

/// Seam 1 on synthetic logs: the hero-pick offer, rerolls, skins, the pick, the tribe
/// adjustment, tiers, window fallback and the stale badge, without the private fixtures.
@Suite("Hero pick stats on synthetic logs")
struct HeroPickSyntheticTests {
    static let utc = TimeZone(identifier: "UTC")!
    static let updatedAt = Date(timeIntervalSince1970: 1_790_122_226)  // 2026-09-23T00:10:26Z

    static func stat(
        _ hero: String, games: Int = 1000, average: Double = 4, win: Double = 15, top4Rest: Double = 40,
        tribes: [FirestoneHeroStat.TribeStat] = []
    ) -> FirestoneHeroStat {
        // 1st = win, 2nd–4th share top4Rest, 5th–8th share the rest.
        let rest = (100 - win - top4Rest) / 4
        let placements = [win, top4Rest / 3, top4Rest / 3, top4Rest / 3, rest, rest, rest, rest]
        return FirestoneHeroStat(
            heroCardId: hero, dataPoints: games, totalOffered: games * 2, totalPicked: games, averagePosition: average,
            placementDistribution: placements.enumerated().map { .init(rank: $0.offset + 1, percentage: $0.element) },
            tribeStats: tribes
        )
    }

    static func set(_ windows: [HeroStatsWindow: [FirestoneHeroStat]], updatedAt: Date = updatedAt) -> HeroStatsSet {
        HeroStatsSet(files: windows.mapValues { stats in
            FirestoneHeroStatsFile(lastUpdateDate: updatedAt, dataPoints: stats.map(\.dataPoints).reduce(0, +), heroStats: stats)
        })
    }

    /// Four heroes, averages 3.8…4.1, in past-three.
    static let fourHeroes = set([.pastThree: [
        stat("BG_A", average: 3.8), stat("BG_B", average: 3.9), stat("BG_C", average: 4.0), stat("BG_D", average: 4.1),
    ]])

    static func pickScreen(_ heroes: [String] = ["BG_A", "BG_B", "BG_C", "BG_D"], locked: Set<Int> = [], extra: [Int: [String]] = [:]) -> SyntheticLog {
        var log = SyntheticLog()
        log.createGame(gameType: "GT_BATTLEGROUNDS")
        log.offerHeroes(heroes, locked: locked, extra: extra)
        return log
    }

    static func engine(
        _ log: SyntheticLog, stats: HeroStatsSet? = fourHeroes, cards: CardDB? = nil, pool: MinionPool? = nil,
        session: String? = nil
    ) throws -> TavernEngine {
        let session = try session.map { try #require(LogSession(directory: URL(filePath: "/tmp/Logs/\($0)"), timeZone: utc)) }
        var engine = TavernEngine(pool: pool, session: session, timeZone: utc)
        engine.useHeroStats(stats, cards: cards)
        for line in log.lines { engine.ingest(line) }
        return engine
    }

    @Test("The offered heroes show left to right with average, tier, top-4 and win %, and a hero without stats shows no data")
    func offer() throws {
        let engine = try Self.engine(Self.pickScreen(["BG_B", "BG_UNKNOWN", "BG_A", "BG_D"], locked: [105, 108]))
        let pick = try #require(engine.state.game?.heroPick)
        #expect(pick.offers.map(\.cardID) == ["BG_B", "BG_UNKNOWN", "BG_A", "BG_D"])
        #expect(pick.offers.map(\.isLocked) == [true, false, false, true])
        #expect(pick.offers[1].stats == nil)
        let b = try #require(pick.offers[0].stats)
        #expect(b.averagePlacement == 3.9)
        #expect(b.baseAveragePlacement == 3.9)
        #expect(b.tribeModifier == 0)
        #expect(b.winPercent == 15)
        #expect(b.top4Percent == 55)
        #expect(b.placements.count == 8)
        #expect(abs(b.placements.reduce(0, +) - 100) < 0.5)
        #expect(b.dataPoints == 1000)
        #expect(b.window == .pastThree)
        #expect(pick.tribeAdjustment == .none)
        #expect(pick.mmrPercentile == 100)
        #expect(pick.chosenCardID == nil)
        #expect(pick.statsUpdatedAt == "2026-09-23T00:10:26Z")
    }

    @Test("A reroll updates the offer and its stats at once")
    func reroll() throws {
        var log = Self.pickScreen()
        let before = try Self.engine(log)
        #expect(before.state.game?.heroPick?.offers[1].stats?.averagePlacement == 3.9)
        log.rerollHero(106, from: "BG_B", to: "BG_D")
        let after = try Self.engine(log)
        let pick = try #require(after.state.game?.heroPick)
        #expect(pick.offers.map(\.cardID) == ["BG_A", "BG_D", "BG_C", "BG_D"])
        #expect(pick.offers[1].stats?.averagePlacement == 4.1)
    }

    @Test("Skinned heroes show the base hero's stats: by BACON_SKIN_PARENT_ID with card data, else by the _SKIN_ name")
    func skins() throws {
        let stats = Self.set([.pastThree: [Self.stat("BG20_HERO_202", average: 3.7), Self.stat("TB_BaconShop_HERO_94", average: 4.3)]])
        let log = Self.pickScreen(
            ["BG20_HERO_202_SKIN_B4", "TB_BaconShop_HERO_94_SKIN_F"],
            extra: [105: ["tag=BACON_SKIN value=1", "tag=BACON_SKIN_PARENT_ID value=71908"]]
        )
        let engine = try Self.engine(log, stats: stats, cards: PoolFixture.cards)
        let offers = try #require(engine.state.game?.heroPick?.offers)
        #expect(offers.map(\.baseCardID) == ["BG20_HERO_202", "TB_BaconShop_HERO_94"])
        #expect(offers.map { $0.stats?.averagePlacement } == [3.7, 4.3])
        #expect(offers[0].name == "Mystical Mentor Nguyen")

        // Without card data the naming convention still finds the base hero.
        let bare = try Self.engine(log, stats: stats)
        #expect(bare.state.game?.heroPick?.offers.map(\.baseCardID) == ["BG20_HERO_202", "TB_BaconShop_HERO_94"])
    }

    @Test("Once picked, the view names the pick; from the first recruit phase on there is no hero pick")
    func pickResolves() throws {
        var log = Self.pickScreen()
        log.chooseHero(107, cardID: "BG_C")
        let chosen = try Self.engine(log)
        #expect(chosen.state.game?.heroPick?.chosenCardID == "BG_C")
        log.pickHero(cardID: "BG_C")
        log.turn(1)
        var engine = try Self.engine(log)
        engine.finish()
        #expect(engine.state.game?.phase == .recruit)
        #expect(engine.state.game?.heroPick == nil)
        #expect(engine.timeline.contains { $0.state.game?.heroPick?.offers.count == 4 })
    }

    @Test("Without hero stats the hero pick stays out of the view")
    func noStats() throws {
        let engine = try Self.engine(Self.pickScreen(), stats: nil)
        #expect(engine.state.game != nil)
        #expect(engine.state.game?.heroPick == nil)
        let json = try JSONEncoder().encode(engine.state)
        #expect(!String(decoding: json, as: UTF8.self).contains("\"heroPick\":"))
    }

    @Test("The tribe adjustment is Firestone's: impacts of the lobby's tribes summed, noisy rows and forced tribes left out")
    func tribeAdjustment() throws {
        func row(_ race: String, _ games: Int, missing: Int, impact: Double) -> FirestoneHeroStat.TribeStat {
            .init(tribe: HS.Race(name: race)!.rawValue, dataPoints: games, dataPointsOnMissingTribe: missing, impactAveragePosition: impact)
        }
        let hero = Self.stat("BG_A", games: 1000, average: 4.0, tribes: [
            row("DRAGON", 400, missing: 600, impact: -0.20),     // counts
            row("QUILBOAR", 300, missing: 700, impact: 0.05),    // counts
            row("UNDEAD", 40, missing: 960, impact: -0.50),      // too few games with it (≤ 1000/20)
            row("ELEMENTAL", 980, missing: 20, impact: 0.30),    // too few games without it (≤ 980/20)
            row("ABERRATION", 900, missing: 100, impact: -0.40), // forced into every lobby: left out
            row("BEAST", 400, missing: 600, impact: 0.70),       // not in the lobby
        ])
        let stats = Self.set([.pastThree: [hero, Self.stat("BG_B"), Self.stat("BG_C"), Self.stat("BG_D")]])
        let lobby = ["ABERRATION", "DRAGON", "ELEMENTAL", "QUILBOAR", "UNDEAD"].map { HS.Race(name: $0)! }

        var engine = try Self.engine(Self.pickScreen(), stats: stats, pool: PoolFixture.pool, session: "Hearthstone_2026_09_23_01_00_00")
        #expect(engine.state.game?.heroPick?.tribeAdjustment == .estimated)
        engine.ingestScreenTribes(ScreenTribeReading(tribes: lobby))
        let pick = try #require(engine.state.game?.heroPick)
        #expect(pick.tribeAdjustment == .exact)
        let a = try #require(pick.offers[0].stats)
        #expect(a.baseAveragePlacement == 4.0)
        #expect(a.tribeModifier == -0.15)
        #expect(a.averagePlacement == 3.85)

        // No pool: no tribe information, no adjustment.
        let unadjusted = try Self.engine(Self.pickScreen(), stats: stats)
        #expect(unadjusted.state.game?.heroPick?.offers[0].stats?.averagePlacement == 4.0)
    }

    @Test("Tiers follow the field's mean and spread: S below μ−3σ … E from μ+2σ")
    func tiers() throws {
        // μ = 4.0, σ = √0.2 ≈ 0.447: 3.0 is A (μ−3σ ≈ 2.66 ≤ 3.0 < μ−1.5σ ≈ 3.33), 5.0 is E (≥ μ+2σ ≈ 4.89).
        var heroes = [Self.stat("BG_A", average: 3.0), Self.stat("BG_E", average: 5.0)]
        heroes += (1...8).map { Self.stat("BG_M\($0)", average: 4.0) }
        heroes.append(Self.stat("BG_TINY", games: 29, average: 1.0))  // under 30 games: not in the field
        let engine = try Self.engine(Self.pickScreen(["BG_A", "BG_M1", "BG_E", "BG_TINY"]), stats: Self.set([.pastThree: heroes]))
        let offers = try #require(engine.state.game?.heroPick?.offers)
        #expect(offers.map { $0.stats?.tier } == [.A, .C, .E, .S])
    }

    @Test("Heroes with under 300 games in the past three days fall back to the past seven, then to the last patch")
    func windowFallback() throws {
        let stats = Self.set([
            .pastThree: [Self.stat("BG_A", games: 2000, average: 3.1), Self.stat("BG_B", games: 120, average: 3.2),
                         Self.stat("BG_C", games: 100, average: 3.3)],
            .pastSeven: [Self.stat("BG_B", games: 450, average: 4.2), Self.stat("BG_C", games: 200, average: 4.3)],
            .lastPatch: [Self.stat("BG_C", games: 900, average: 5.3), Self.stat("BG_D", games: 700, average: 5.4)],
        ])
        let engine = try Self.engine(Self.pickScreen(), stats: stats)
        let offers = try #require(engine.state.game?.heroPick?.offers)
        #expect(offers.map { $0.stats?.window } == [.pastThree, .pastSeven, .lastPatch, .lastPatch])
        #expect(offers.map { $0.stats?.averagePlacement } == [3.1, 4.2, 5.3, 5.4])
        #expect(offers.map { $0.stats?.dataPoints } == [2000, 450, 900, 700])
    }

    @Test("The stale badge shows when the stats are more than 24 hours old at the game's time")
    func staleBadge() throws {
        let fresh = try Self.engine(Self.pickScreen(), session: "Hearthstone_2026_09_23_23_00_00")
        #expect(fresh.state.game?.heroPick?.isStale == false)
        let stale = try Self.engine(Self.pickScreen(), session: "Hearthstone_2026_09_24_01_00_00")
        #expect(stale.state.game?.heroPick?.isStale == true)
        #expect(HeroStatsSet.isStale(updatedAt: Self.updatedAt, now: Self.updatedAt.addingTimeInterval(24 * 3600 + 1)))
        #expect(!HeroStatsSet.isStale(updatedAt: Self.updatedAt, now: Self.updatedAt.addingTimeInterval(23 * 3600)))
    }

    @Test("Discover options count as evidence of their tribe")
    func discoverOptionsAreTribeEvidence() throws {
        var log = TribeSyntheticTests.recruiting()
        let before = try TribeSyntheticTests.replay(log)
        let quilboar = try #require(TribeSyntheticTests.percent(before, "QUILBOAR"))
        #expect(PoolFixture.pool.minion("BG20_101") != nil)  // Roadboar, a Quilboar
        log.choices(id: 2, type: "GENERAL", source: "[entityName=Battlegrounds Dark Gift [DNT] id=1230 zone=PLAY zonePos=0 cardId=BG36_MidGameEffect_010 player=6]",
                    options: [(1231, "BG20_101", "SETASIDE"), (1232, "BG_NOT_A_CARD", "SETASIDE")])
        let after = try TribeSyntheticTests.replay(log)
        let raised = try #require(TribeSyntheticTests.percent(after, "QUILBOAR"))
        #expect(quilboar < 50)
        #expect(raised > 90)
    }
}
