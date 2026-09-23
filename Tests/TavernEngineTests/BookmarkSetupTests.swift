import Foundation
import HSLog
import Testing
import TavernEngine

/// Seam 1: a bookmark replays exactly when the replay gets what the live engine had besides the
/// log: the pool, builds and hero stats (`EngineSetup`), and the hero-pick banner readings,
/// which are kept in the bookmark and in the game's record and taken in again at their lines.
@Suite("Bookmarks with the live engine's setup and screen readings")
struct BookmarkSetupTests {
    static let banner: [HS.Race] = [.aberration, .demon, .elemental, .murloc, .quilboar]

    /// What `LivePipeline` gives every engine once the app's data has loaded.
    static let liveSetup = EngineSetup(
        pool: PoolFixture.pool, builds: BuildFixture.catalog, heroStats: HeroStatsFixture.stats, heroCards: PoolFixture.cards
    )

    static func tribes(_ entry: TimelineEntry?) -> TribesView? { entry?.state.game?.tribes }

    @Test("A bookmark taken after a screen reading replays to the identical snapshot with the live setup, and only with it")
    func replaysWithSetupAndReadings() throws {
        let (url, session) = try BookmarkTests.twoGames().write()
        let entry = try #require(PowerLogEntryPoint.find(in: url))
        var live = try LiveRead(url: url, session: session, caughtUpAt: entry.line, setup: Self.liveSetup)
        // The banner is read once the hero pick is on screen.
        while live.engine.state.game == nil { live.follow(through: live.engine.linesRead + 1) }
        let readAt = live.engine.linesRead
        live.read(ScreenTribeReading(tribes: Self.banner))
        live.follow(through: live.lines.count)

        let bookmark = try live.bookmark(note: "tribes from the banner")
        #expect(Self.tribes(bookmark.shown)?.source == .screen)
        let readings = try #require(bookmark.screenTribes)
        #expect(readings.map(\.reading.tribes) == [Self.banner])
        #expect(readings.first?.line == readAt && readings.first?.session == session.name)

        // The debug window's replay and the export use the live setup: the identical snapshot.
        #expect(try live.replay(bookmark).timeline.only == bookmark.shown)
        // Without it, or without the reading, the tribes come out otherwise.
        let bare = try TavernEngine.replay(bookmark, powerLog: url)
        #expect(bare.timeline.only != bookmark.shown && Self.tribes(bare.timeline.only) == nil)
        var unread = bookmark
        unread.screenTribes = nil
        let inferred = try TavernEngine.replay(unread, powerLog: url, setup: Self.liveSetup).timeline.only
        #expect(inferred != bookmark.shown && Self.tribes(inferred)?.source == .inferred)

        // Exported, the case keeps the readings and verifies against the live setup.
        let root = BookmarkTests.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let exported = try BookmarkExport.export(bookmark, powerLog: url, into: root, setup: Self.liveSetup)
        #expect(exported.goldenCase.screenTribes == readings)
        #expect(try exported.goldenCase.replay(powerLog: exported.logFile, setup: Self.liveSetup) == exported.goldenCase.expected)
        #expect(throws: BookmarkReplayError.replayDiffers) {
            try BookmarkExport.export(bookmark, powerLog: url, name: "bare", into: root)
        }
    }

    @Test("A screen reading is kept in the game's record, and a game resumed in the next session takes it in again")
    func readingsSurviveResume() throws {
        let directory = BookmarkTests.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GameRecordStore(directory: directory)

        // Session A: the banner is read at the hero pick; the client then restarts mid-game.
        let first = GameRecordTests.afterFirstCombat()
        var engine = TavernEngine(setup: Self.liveSetup, session: try GameRecordTests.session("Hearthstone_2026_09_22_21_08_40"),
                                  timeZone: .gmt)
        for line in first.lines.prefix(first.lines.count / 2) { engine.ingest(line) }
        engine.ingestScreenTribes(ScreenTribeReading(tribes: Self.banner))
        for line in first.lines.dropFirst(first.lines.count / 2) { engine.ingest(line) }
        for record in engine.takeUnsavedRecords() { try store.save(record) }
        let saved = try #require(store.latestInProgress())
        #expect(saved.screenTribes.map(\.reading.tribes) == [Self.banner])

        // Session B resends the game: its tribes are the banner's again, from the record alone.
        var next = SyntheticLog()
        next.time = "21:20:30.0000000"
        next.reconnect(turn: 3)
        let (url, session) = try next.write(session: "Hearthstone_2026_09_22_21_20_00")
        let live = try LiveRead(url: url, session: session, resuming: saved, caughtUpAt: next.lines.count, setup: Self.liveSetup)
        let tribes = try #require(live.engine.state.game?.tribes)
        #expect(tribes.source == .screen && tribes.confirmedNames == Self.banner.map(\.description).sorted())
        #expect(live.engine.inProgressRecord?.screenTribes == saved.screenTribes, "still in the record")

        // A bookmark here carries the reading in its resumed record, and replays to the same moment.
        let bookmark = try live.bookmark()
        #expect(bookmark.screenTribes == nil && bookmark.resumed?.screenTribes == saved.screenTribes)
        #expect(try live.replay(bookmark).timeline.only == bookmark.shown)
    }

    @Test("A record with no screen readings is written as before, and older records still load")
    func recordFormat() throws {
        let directory = BookmarkTests.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GameRecordStore(directory: directory)
        let engine = GameRecordTests.replay(GameRecordTests.afterFirstCombat().lines)
        let record = try #require(engine.records.only)
        try store.save(record)
        let json = try String(contentsOf: store.url(for: record), encoding: .utf8)
        #expect(!json.contains("screenTribes"))
        #expect(store.load(seed: try #require(record.gameSeed))?.screenTribes == [])
    }
}
