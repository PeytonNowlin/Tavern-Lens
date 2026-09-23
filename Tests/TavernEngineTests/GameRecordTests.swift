import Foundation
import HSLog
import Testing
import TavernEngine

/// Seam 1 on synthetic logs: per-game records, reconnects (same `GAME_SEED`), games
/// resumed across client restarts, catch-up from the entry point, and record dates.
@Suite("Game records and reconnects on synthetic logs")
struct GameRecordTests {
    static let utc = TimeZone(identifier: "UTC")!
    static let board = LobbySyntheticTests.board

    /// A lobby game that has fought P3 on turn 1 and is in turn 2's recruit phase.
    static func afterFirstCombat() -> SyntheticLog {
        var log = LobbySyntheticTests.lobbyGame()
        log.startCombat(bgTurn: 1, opponent: 3, name: LobbySyntheticTests.opponentName, heroID: 800, board: board)
        log.endCombat(board: board, nextOpponent: 4)
        log.turn(3)
        return log
    }

    static func session(_ name: String) throws -> LogSession {
        try #require(LogSession(directory: URL(filePath: "/tmp/Logs/\(name)"), timeZone: utc))
    }

    static func replay(_ lines: [String], session: LogSession? = nil, resuming record: GameRecord? = nil) -> TavernEngine {
        var engine = TavernEngine(session: session, timeZone: utc)
        if let record { engine.resume(record) }
        for line in lines { engine.ingest(line) }
        engine.finish()
        return engine
    }

    static func opponentBoard(_ engine: TavernEngine, _ playerID: Int = 3) -> LastSeenBoardView? {
        engine.state.game?.lobby.first { $0.playerID == playerID }?.lastSeenBoard
    }

    // MARK: - Reconnect in the same log

    @Test("A reconnect (same seed) keeps the last-seen opponent boards and names", arguments: [true, false])
    func reconnectKeepsHistory(withMetadata: Bool) throws {
        var log = Self.afterFirstCombat()
        let before = Self.replay(log.lines)
        let seen = try #require(Self.opponentBoard(before))
        #expect(seen.cards.map(\.cardID) == Self.board.map(\.cardID))

        log.time = "21:15:02.0000000"
        log.reconnect(turn: 3, metadata: withMetadata)
        let engine = Self.replay(log.lines)

        #expect(engine.state.status == .inGame)
        #expect(engine.state.game?.bgTurn == 2)
        #expect(Self.opponentBoard(engine) == seen)
        #expect(engine.state.game?.lobby.first { $0.playerID == 3 }?.displayName == LobbySyntheticTests.opponentName)
        let game = try #require(engine.games.only)
        #expect(game.outcome == .inProgress)
        let reconnect = try #require(game.reconnects.only)
        #expect(!reconnect.acrossSessions)
        #expect(reconnect.resumedAt.time == "21:15:02.0000000")
        #expect(reconnect.lastBefore.line < reconnect.resumedAt.line)
        #expect(try #require(engine.records.only).journal.boardsSeen.count == 1)
    }

    @Test("After a reconnect, the next combat is captured and the turn snapshots carry on")
    func reconnectThenCombat() throws {
        var log = Self.afterFirstCombat()
        log.reconnect(turn: 3, metadata: false)
        let second: [SyntheticLog.Minion] = [.init(id: 710, cardID: "BG_Second", atk: 1, health: 1)]
        log.startCombat(bgTurn: 2, opponent: 4, name: "Another Opponent", heroID: 801, board: second)
        let engine = Self.replay(log.lines)

        #expect(Self.opponentBoard(engine, 3)?.bgTurn == 1)
        #expect(Self.opponentBoard(engine, 4)?.cards.map(\.cardID) == ["BG_Second"])
        let record = try #require(engine.records.only)
        #expect(record.journal.boardsSeen.map(\.playerID) == [3, 4])
        #expect(record.journal.turns.map(\.bgTurn) == [1, 2])
    }

    @Test("A different seed starts a new game; the unfinished one is kept as abandoned")
    func differentSeedAbandons() throws {
        var log = Self.afterFirstCombat()
        log.newGame(seed: 42)
        let engine = Self.replay(log.lines)

        #expect(engine.games.map(\.outcome) == [.abandoned, .inProgress])
        #expect(engine.games[0].end == nil && engine.games[0].placement == nil)
        #expect(engine.games.map(\.gameSeed) == [SyntheticLog.defaultSeed, 42])
        #expect(Self.opponentBoard(engine) == nil)
        #expect(engine.records[0].journal.boardsSeen.count == 1)
    }

    @Test("Outcomes: complete at STATE=COMPLETE, conceded on the local concede")
    func outcomes() {
        #expect(TavernEngine.replay(lines: SyntheticLog.soloGame().lines).games.map(\.outcome) == [.complete])
        var conceded = LobbySyntheticTests.lobbyGame()
        conceded.localTag("3479", "1")
        conceded.endTaskList()
        let result = TavernEngine.replay(lines: conceded.lines)
        #expect(result.games.map(\.outcome) == [.conceded])
        #expect(result.records.first?.journal.finalLobby?.count == 8)
    }

    // MARK: - Across sessions (the client restarted)

    @Test("A game resumed in the next session's log keeps its boards, through the record store")
    func resumeAcrossSessions() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "TavernLensRecords-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GameRecordStore(directory: directory)

        let first = try Self.session("Hearthstone_2026_09_22_21_08_40")
        var log = Self.afterFirstCombat()
        var engine = Self.replay(log.lines, session: first)
        for record in engine.takeUnsavedRecords() { try store.save(record) }
        let saved = try #require(store.latestInProgress())
        #expect(saved.journal.boardsSeen.count == 1)

        // The new client launch's log starts with the resent game.
        let second = try Self.session("Hearthstone_2026_09_22_21_20_00")
        var next = SyntheticLog()
        next.time = "21:20:30.0000000"
        next.reconnect(turn: 3)
        engine = Self.replay(next.lines, session: second, resuming: saved)

        let seen = try #require(Self.opponentBoard(engine))
        #expect(seen.cards.map(\.cardID) == Self.board.map(\.cardID))
        #expect(engine.state.game?.lobby.first { $0.playerID == 3 }?.displayName == LobbySyntheticTests.opponentName)
        let record = try #require(engine.records.only)
        #expect(record.sessions == [first.name, second.name])
        #expect(record.startedAt == saved.startedAt)
        #expect(record.summary.reconnects.map(\.acrossSessions) == [true])

        // A different game in the next session instead: the saved one is abandoned.
        log = SyntheticLog()
        log.newGame(seed: 42)
        engine = Self.replay(log.lines, session: second, resuming: saved)
        for record in engine.takeUnsavedRecords() { try store.save(record) }
        #expect(store.load(seed: SyntheticLog.defaultSeed)?.outcome == .abandoned)
        #expect(store.latestInProgress()?.gameSeed == 42)
    }

    @Test("Reading the same log again over its saved record changes nothing")
    func rereadIsIdempotent() throws {
        let session = try Self.session("Hearthstone_2026_09_22_21_08_40")
        var log = Self.afterFirstCombat()
        log.reconnect(turn: 3)
        let first = Self.replay(log.lines, session: session)
        let saved = try #require(first.inProgressRecord)

        let again = Self.replay(log.lines, session: session, resuming: saved)
        let record = try #require(again.records.only)
        #expect(record.summary == saved.summary)
        #expect(record.journal == saved.journal)
        #expect(record.sessions == [session.name])
        #expect(again.state == first.state)
    }

    // MARK: - Catch-up

    @Test("Catch-up from the entry point rebuilds the full replay's state and publishes once")
    func catchUpFromEntryPoint() throws {
        var log = SyntheticLog.soloGame()
        log.createGame(gameType: "GT_RANKED", seed: 7)  // another mode in between
        log.turn(1)
        log.newGame(seed: 42)
        log.sevenOpponents()
        log.turn(1)
        log.startCombat(bgTurn: 1, opponent: 3, name: LobbySyntheticTests.opponentName, heroID: 800, board: Self.board)
        log.reconnect(seed: 42, turn: 2)
        let full = TavernEngine.replay(lines: log.lines)

        let bytes = Data(log.lines.joined(separator: "\n").utf8 + [0x0A])
        let entry = try #require(PowerLogEntryPoint.find(in: bytes))
        #expect(entry.gameSeed == 42)
        #expect(log.lines[entry.line - 1].contains("GameState.DebugPrintPower() - CREATE_GAME"))

        var engine = TavernEngine()
        engine.skipLines(entry.line - 1)
        engine.beginCatchUp()
        for line in log.lines[(entry.line - 1)...] { engine.ingest(line) }
        #expect(engine.timeline.isEmpty)
        engine.endCatchUp()

        #expect(engine.timeline.count == 1)
        #expect(engine.timeline.last?.state == full.timeline.last?.state)
        #expect(engine.timeline.last?.position.line == log.lines.count)
        #expect(Self.opponentBoard(engine) != nil)
        #expect(engine.games.only == full.games.last)
        #expect(engine.games.only?.reconnects.count == 1)
    }

    // MARK: - Persistence and dates

    @Test("Records come out at checkpoints and at game end, and outlive the log")
    func recordsOutliveTheLog() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "TavernLensRecords-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessionDirectory = root.appending(path: "Logs/Hearthstone_2026_09_22_21_08_40")
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        let session = try #require(LogSession(directory: sessionDirectory, timeZone: Self.utc))
        let store = GameRecordStore(directory: root.appending(path: "Games"))

        var log = Self.afterFirstCombat()
        var engine = TavernEngine(session: session, timeZone: Self.utc)
        for line in log.lines { engine.ingest(line) }
        let midGame = engine.takeUnsavedRecords()
        #expect(midGame.map(\.outcome) == [.inProgress])
        #expect(midGame.first?.journal.boardsSeen.count == 1)
        #expect(engine.takeUnsavedRecords().isEmpty)

        log = SyntheticLog()
        log.completeGame()
        for line in log.lines { engine.ingest(line) }
        let atEnd = try #require(engine.takeUnsavedRecords().only)
        #expect(atEnd.outcome == .complete)
        #expect(atEnd.summary.placement == 3)
        try store.save(atEnd)

        try "stand-in for the raw log".write(to: session.powerLog, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: root.appending(path: "Logs"))
        let loaded = try #require(store.load(seed: SyntheticLog.defaultSeed))
        Self.expectSame(loaded, atEnd)
        #expect(store.all().count == 1)
    }

    /// Equal, with dates to the millisecond the store keeps.
    static func expectSame(_ a: GameRecord, _ b: GameRecord, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(a.summary == b.summary, sourceLocation: sourceLocation)
        #expect(a.journal == b.journal, sourceLocation: sourceLocation)
        #expect(a.sessions == b.sessions, sourceLocation: sourceLocation)
        for (x, y) in [(a.startedAt, b.startedAt), (a.endedAt, b.endedAt), (a.updatedAt, b.updatedAt)] {
            #expect((x == nil) == (y == nil), sourceLocation: sourceLocation)
            if let x, let y { #expect(abs(x.timeIntervalSince(y)) < 0.001, sourceLocation: sourceLocation) }
        }
    }

    @Test("Timestamps after midnight get the next day's date")
    func midnightRollover() throws {
        let session = try Self.session("Hearthstone_2026_09_22_23_58_30")
        var log = SyntheticLog()
        log.time = "23:59:10.5000000"
        log.createGame(gameType: "GT_BATTLEGROUNDS")
        log.pickHero()
        log.turn(1)
        log.time = "00:04:20.2500000"
        log.completeGame()
        let record = try #require(Self.replay(log.lines, session: session).records.only)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        let started = try #require(record.startedAt)
        let ended = try #require(record.endedAt)
        #expect(calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: started)
            == DateComponents(year: 2026, month: 9, day: 22, hour: 23, minute: 59, second: 10))
        #expect(calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: ended)
            == DateComponents(year: 2026, month: 9, day: 23, hour: 0, minute: 4, second: 20))
        #expect(record.summary.end?.time == "00:04:20.2500000")
    }
}
