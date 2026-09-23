import Foundation
import HSLog
import Testing
import TavernEngine

/// Seam 1 on synthetic logs: the pool's self-heal, forced tribes with an end date,
/// reconnects and games without a pool, without the private fixtures.
@Suite("Lobby tribes on synthetic logs")
struct TribeSyntheticTests {
    static let utc = TimeZone(identifier: "UTC")!

    /// A game in its first recruit phase, the local player at tier 1.
    static func recruiting(seed: Int = SyntheticLog.defaultSeed) -> SyntheticLog {
        var log = SyntheticLog()
        log.createGame(gameType: "GT_BATTLEGROUNDS", seed: seed)
        log.pickHero()
        log.tag(SyntheticLog.pickedHeroID, "PLAYER_TECH_LEVEL", "1")
        log.turn(1)
        return log
    }

    static func replay(_ log: SyntheticLog, pool: MinionPool? = PoolFixture.pool, session: String? = nil) throws -> TavernEngine {
        let session = try session.map { try #require(LogSession(directory: URL(filePath: "/tmp/Logs/\($0)"), timeZone: utc)) }
        var engine = TavernEngine(pool: pool, session: session, timeZone: utc)
        for line in log.lines { engine.ingest(line) }
        engine.finish()
        return engine
    }

    static func percent(_ engine: TavernEngine, _ tribe: String) -> Int? {
        engine.state.game?.tribes?.tribes.first { $0.tribe == tribe }?.percent
    }

    @Test("A shop minion the game flags as in the pool but ours lacks is added for the game, with a diagnostic")
    func selfHeal() throws {
        var overrides = PoolFixture.overrides
        overrides.minionPool["BG31_815"] = 0  // pretend Dune Dweller (Elemental, T1) isn't in our pool
        let pool = MinionPool.compose(cards: PoolFixture.cards, metaPeriod: MetaPeriod.bundled(), overrides: overrides)
        #expect(!pool.contains("BG31_815"))

        var log = Self.recruiting()
        log.shopCard(200, "BG31_815", position: 1, atk: 3, health: 2, extra: ["TECH_LEVEL=1", "IS_BACON_POOL_MINION=1"])
        log.endTaskList()
        let engine = try Self.replay(log, pool: pool)
        #expect(engine.poolDrift == [PoolDrift(cardID: "BG31_815", name: "Dune Dweller", tier: 1, gameSeed: SyntheticLog.defaultSeed)])
        // It counts as evidence at once: Elemental is now likely.
        #expect(try #require(Self.percent(engine, "ELEMENTAL")) > 90)

        // Unflagged, it is left out (it could be a token or an effect's card).
        var unflagged = Self.recruiting()
        unflagged.shopCard(200, "BG31_815", position: 1, extra: ["TECH_LEVEL=1"])
        unflagged.endTaskList()
        let ignored = try Self.replay(unflagged, pool: pool)
        #expect(ignored.poolDrift.isEmpty)
        #expect(Self.percent(ignored, "ELEMENTAL") == 44)
    }

    @Test("Frozen minions carried into the next turn aren't new draws; each entity counts once")
    func frozenCarryOver() throws {
        var once = Self.recruiting()
        once.shopCard(200, "BG28_300", position: 1, extra: ["TECH_LEVEL=1", "IS_BACON_POOL_MINION=1", "FROZEN=1"])
        once.endTaskList()
        once.endTaskList()
        once.turn(2)
        once.turn(3)
        let one = try Self.replay(once)

        var twice = Self.recruiting()
        twice.shopCard(200, "BG28_300", position: 1, extra: ["TECH_LEVEL=1", "IS_BACON_POOL_MINION=1", "FROZEN=1"])
        twice.endTaskList()
        twice.turn(2)
        twice.turn(3)
        // The same card, frozen, on a new entity next turn: a carry-over, not a second draw.
        twice.shopCard(201, "BG28_300", position: 1, extra: ["TECH_LEVEL=1", "IS_BACON_POOL_MINION=1", "FROZEN=1"])
        twice.endTaskList()
        #expect(try Self.replay(twice).tribeEstimate?.shopDraws == 1)
        #expect(one.tribeEstimate?.shopDraws == 1)

        // A second copy that wasn't frozen is a new draw.
        var fresh = Self.recruiting()
        fresh.shopCard(200, "BG28_300", position: 1, extra: ["TECH_LEVEL=1", "IS_BACON_POOL_MINION=1"])
        fresh.endTaskList()
        fresh.turn(2)
        fresh.turn(3)
        fresh.shopCard(201, "BG28_300", position: 1, extra: ["TECH_LEVEL=1", "IS_BACON_POOL_MINION=1"])
        fresh.endTaskList()
        #expect(try Self.replay(fresh).tribeEstimate?.shopDraws == 2)
    }

    @Test("Forced tribes end on their date: after it, Aberration is one of ten, not forced")
    func forcedTribeEnds() throws {
        let during = try Self.replay(Self.recruiting(), session: "Hearthstone_2026_09_25_20_00_00")
        let aberration = try #require(during.state.game?.tribes?.tribes.first { $0.tribe == "ABERRATION" })
        #expect(aberration.isForced && aberration.confidence == .confirmed)
        #expect(Self.percent(during, "BEAST") == 44)

        let after = try Self.replay(Self.recruiting(), session: "Hearthstone_2026_10_10_20_00_00")
        let tribes = try #require(after.state.game?.tribes)
        #expect(tribes.tribes.count == 10)
        #expect(tribes.tribes.allSatisfy { !$0.isForced && $0.percent == 50 })
    }

    @Test("A reconnect keeps the game's evidence; a new game starts over")
    func reconnectAndNewGame() throws {
        var log = Self.recruiting()
        log.shopCard(200, "BG28_300", position: 1, extra: ["TECH_LEVEL=1", "IS_BACON_POOL_MINION=1"])
        log.endTaskList()
        let before = try #require(try Self.replay(log).state.game?.tribes)

        var reconnected = log
        reconnected.reconnect(turn: 1)
        reconnected.shopCard(200, "BG28_300", position: 1, extra: ["TECH_LEVEL=1", "IS_BACON_POOL_MINION=1"])
        reconnected.endTaskList()
        let engine = try Self.replay(reconnected)
        #expect(engine.state.game?.tribes == before)
        #expect(engine.tribeEstimate?.shopDraws == 1)

        var next = log
        next.newGame(seed: 99)
        let fresh = try Self.replay(next)
        #expect(fresh.tribeEstimate?.shopDraws == 0)
        #expect(Self.percent(fresh, "UNDEAD") == 44)
    }

    @Test("Without a pool there are no tribes, and the view's JSON has no tribes key")
    func noPool() throws {
        var log = Self.recruiting()
        log.shopCard(200, "BG28_300", position: 1, extra: ["TECH_LEVEL=1", "IS_BACON_POOL_MINION=1"])
        log.endTaskList()
        let engine = try Self.replay(log, pool: nil)
        let game = try #require(engine.state.game)
        #expect(game.tribes == nil)
        #expect(engine.tribeEstimate == nil)
        let json = String(decoding: try JSONEncoder().encode(game), as: UTF8.self)
        #expect(!json.contains("tribes"))
        // A screen reading outside a game is ignored.
        var idle = TavernEngine(pool: PoolFixture.pool)
        idle.ingestScreenTribes(ScreenTribeReading(tribes: [.beast]))
        #expect(idle.state == .noGame)
    }

    @Test("The tribe view round-trips through JSON")
    func codable() throws {
        var log = Self.recruiting()
        log.shopCard(200, "BG28_300", position: 1, extra: ["TECH_LEVEL=1", "IS_BACON_POOL_MINION=1"])
        log.endTaskList()
        let tribes = try #require(try Self.replay(log).state.game?.tribes)
        let decoded = try JSONDecoder().decode(TribesView.self, from: JSONEncoder().encode(tribes))
        #expect(decoded == tribes)
        #expect(tribes.tribes.first?.name == "Aberration")
        #expect(TribeView.displayName(.mechanical) == "Mech")
    }
}
