import Foundation
import HSLog
import Testing
import TavernEngine

/// Seam 1 on the captured games: the per-game record, catching up mid-game, and the
/// game Hearthstone was closed in. Skipped when the private fixtures are absent.
@Suite("Game records and catch-up on captured games", .serialized)
struct GameRecordFixtureTests {
    static func session(_ relativePath: String) throws -> LogSession {
        let url = try #require(Fixtures.url(relativePath))
        return try #require(LogSession(directory: url.deletingLastPathComponent()))
    }

    static func localComponents(_ date: Date?) -> DateComponents? {
        date.map { Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: $0) }
    }

    static func temporaryStore() -> GameRecordStore {
        GameRecordStore(directory: FileManager.default.temporaryDirectory.appending(path: "TavernLensRecords-\(UUID().uuidString)"))
    }

    @Test(
        "Full game: a complete record with every turn and every opponent board, dated from the session folder",
        .enabled(if: Fixtures.isAvailable(Fixtures.fullGame), "private fixture log not present")
    )
    func fullGameRecord() throws {
        let session = try Self.session(Fixtures.fullGame)
        let result = try TavernEngine.replay(fileAt: #require(Fixtures.url(Fixtures.fullGame)), session: session)
        let record = try #require(result.records.only)

        #expect(record.summary == result.games.only)
        #expect(record.outcome == .complete)
        #expect(record.summary.placement == 4 && record.summary.placementSource == .final)
        #expect(record.summary.reconnects.isEmpty)
        #expect(record.journal.turns.map(\.bgTurn) == Array(1...12))
        #expect(record.journal.boardsSeen.map(\.bgTurn) == Array(1...12))
        #expect(record.journal.finalLobby?.count == 8)
        #expect(record.journal.turns.allSatisfy { $0.lobby.count == 8 && $0.board.count <= 7 })
        #expect(record.sessions == [session.name])
        #expect(Self.localComponents(record.startedAt)
            == DateComponents(year: 2026, month: 9, day: 22, hour: 21, minute: 9, second: 40))
        #expect(Self.localComponents(record.endedAt)
            == DateComponents(year: 2026, month: 9, day: 22, hour: 21, minute: 33, second: 14))

        let store = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.save(record)
        let size = try #require(try store.url(for: record).resourceValues(forKeys: [.fileSizeKey]).fileSize)
        #expect(size < 512 * 1024, "record is \(size) bytes")
        let seed = try #require(record.gameSeed)
        let loaded = try #require(store.load(seed: seed))
        GameRecordTests.expectSame(loaded, record)
    }

    @Test(
        "Opening the app mid-game rebuilds the same state the live replay had at that line",
        .enabled(if: Fixtures.isAvailable(Fixtures.fullGame), "private fixture log not present")
    )
    func midGameAttach() throws {
        var lines: [String] = []
        try LogFileReader.forEachLine(in: #require(Fixtures.url(Fixtures.fullGame))) { lines.append($0) }
        let live = TavernEngine.replay(lines: lines)
        let timeline = live.timeline

        // Recruit, combat, a turn with a board seen, and the game-over state.
        let cuts = [timeline.count / 4, timeline.count / 2, timeline.count * 3 / 4, timeline.count - 1]
        for index in cuts {
            let expected = timeline[index]
            var engine = TavernEngine()
            engine.beginCatchUp()
            for line in lines.prefix(expected.position.line) { engine.ingest(line) }
            engine.endCatchUp()
            #expect(engine.timeline.count == 1)
            #expect(engine.state == expected.state, "catch-up to line \(expected.position.line) differs")
        }
    }

    @Test(
        "Catch-up of the 36 MB game from its entry point, with the UI suppressed",
        .enabled(if: Fixtures.isAvailable(Fixtures.fullGame), "private fixture log not present")
    )
    func catchUpTime() throws {
        let url = try #require(Fixtures.url(Fixtures.fullGame))
        let clock = ContinuousClock()
        var engine = TavernEngine(session: try Self.session(Fixtures.fullGame))
        let elapsed = try clock.measure {
            let entry = try #require(PowerLogEntryPoint.find(in: url))
            engine.skipLines(entry.line - 1)
            engine.beginCatchUp()
            var line = 0
            try LogFileReader.forEachLine(in: url) { text in
                line += 1
                if line >= entry.line { engine.ingest(text) }
            }
            engine.endCatchUp()
        }
        #expect(engine.state.status == .gameOver)
        #expect(engine.games.only?.placement == 4)
        #expect(engine.linesRead == 270_004)
        #if DEBUG
        // Unoptimised test builds are about 3x slower (1.5 s here, 0.44 s in release); the 2 s budget is for release.
        #expect(elapsed < .seconds(5), "catch-up took \(elapsed)")
        #else
        #expect(elapsed < .seconds(2), "catch-up took \(elapsed)")
        #endif
        print("catch-up of the full game took \(elapsed)")
    }

    @Test(
        "Abandoned game: kept as in progress when the log stops, then abandoned when a different game starts",
        .enabled(if: Fixtures.isAvailable(Fixtures.abandonedGame), "private fixture log not present")
    )
    func abandonedGame() throws {
        let session = try Self.session(Fixtures.abandonedGame)
        let result = try TavernEngine.replay(fileAt: #require(Fixtures.url(Fixtures.abandonedGame)), session: session)
        let record = try #require(result.records.only)
        #expect(record.outcome == .inProgress)
        #expect(record.summary.end == nil && record.summary.placement == nil)
        #expect(record.summary.bgTurn == 3)
        #expect(record.journal.turns.map(\.bgTurn) == [1, 2])
        #expect(record.journal.boardsSeen.count == 2)
        #expect(record.endedAt == nil)
        #expect(result.timeline.last?.state.status == .inGame)

        // The record written as the game went on survives the client quitting.
        let store = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.save(record)
        let pending = try #require(store.latestInProgress())
        #expect(pending.gameSeed == record.gameSeed)

        // The next client launch plays a different game: the old one is abandoned, not lost.
        let next = try #require(LogSession(directory: URL(filePath: "/tmp/Logs/Hearthstone_2026_09_22_22_34_47")))
        var engine = TavernEngine(session: next)
        engine.resume(pending)
        var log = SyntheticLog()
        log.newGame(seed: 42)
        for line in log.lines { engine.ingest(line) }
        for saved in engine.takeUnsavedRecords() { try store.save(saved) }

        let seed = try #require(record.gameSeed)
        let abandoned = try #require(store.load(seed: seed))
        #expect(abandoned.outcome == .abandoned)
        #expect(abandoned.journal == record.journal)
        #expect(abandoned.sessions == [session.name])
        #expect(store.latestInProgress()?.gameSeed == 42)
    }
}
