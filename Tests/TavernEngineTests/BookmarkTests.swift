import Foundation
import HSLog
import Testing
import TavernEngine

/// Seam 1: a feedback bookmark replays to the identical snapshot, is kept in its game's
/// record, and exports as a golden case that replays on its own.
@Suite("Feedback bookmarks on synthetic logs")
struct BookmarkTests {
    static let board = LobbySyntheticTests.board

    /// A finished game, then the game being bookmarked (seed 42): a combat, and two more turns.
    static func twoGames() -> SyntheticLog {
        var log = SyntheticLog.soloGame()
        log.newGame(seed: 42)
        log.sevenOpponents()
        log.turn(1)
        log.startCombat(bgTurn: 1, opponent: 3, name: LobbySyntheticTests.opponentName, heroID: 800, board: board)
        log.endCombat(board: board, nextOpponent: 4)
        log.turn(3)
        log.turn(4)
        log.turn(5)
        return log
    }

    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "TavernLensBookmarks-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test("Every moment shown live replays to the identical snapshot, whenever the app attached")
    func everyMomentReplays() throws {
        let (url, session) = try Self.twoGames().write()
        let entry = try #require(PowerLogEntryPoint.find(in: url))
        #expect(entry.line > 1 && entry.gameSeed == 42)
        let lineCount = try LiveRead(url: url, caughtUpAt: entry.line).lines.count

        var checked = 0
        for attach in stride(from: entry.line, through: lineCount, by: 7) {
            var live = try LiveRead(url: url, session: session, caughtUpAt: attach)
            var seen = -1
            while true {
                if live.engine.timeline.count != seen, live.engine.state.game != nil {
                    seen = live.engine.timeline.count
                    let bookmark = try live.bookmark()
                    #expect(bookmark.gameSeed == 42)
                    #expect(bookmark.cut.session == session.name)
                    #expect(bookmark.cut.startLine == entry.line && bookmark.cut.startByteOffset == entry.byteOffset)
                    let replayed = try TavernEngine.replay(bookmark, powerLog: url)
                    #expect(replayed.timeline.count == 1)
                    #expect(replayed.timeline.last == bookmark.shown,
                            "attached at \(attach), bookmarked line \(bookmark.cut.endLine)")
                    checked += 1
                }
                guard live.engine.linesRead < lineCount else { break }
                live.follow(through: live.engine.linesRead + 1)
            }
        }
        #expect(checked > 20)
    }

    @Test("The cut's byte offsets point at its first line and just past its last")
    func byteOffsets() throws {
        let (url, _) = try Self.twoGames().write()
        var live = try LiveRead(url: url, caughtUpAt: 60)
        live.follow(through: 120)
        let cut = try live.bookmark().cut
        let data = try Data(contentsOf: url)
        let start = try #require(cut.startByteOffset.map(Int.init))
        let end = try #require(cut.endByteOffset.map(Int.init))
        let slice = String(decoding: data[start..<end], as: UTF8.self)
        #expect(slice.hasPrefix(live.lines[cut.startLine - 1] + "\n"))
        #expect(slice.hasSuffix(live.lines[cut.endLine - 1] + "\n"))
        #expect(slice.split(separator: "\n", omittingEmptySubsequences: false).count == cut.endLine - cut.startLine + 2)
    }

    @Test("A game resumed from an earlier session replays with the record carried in")
    func resumedGameReplays() throws {
        // Session A: a combat against P3, saved as an in-progress record.
        let first = GameRecordTests.afterFirstCombat()
        var engine = GameRecordTests.replay(first.lines, session: try GameRecordTests.session("Hearthstone_2026_09_22_21_08_40"))
        let saved = try #require(engine.inProgressRecord)

        // Session B resends the game; P3's board is known only from the carried record.
        var next = SyntheticLog()
        next.time = "21:20:30.0000000"
        next.reconnect(turn: 3)
        let (url, session) = try next.write(session: "Hearthstone_2026_09_22_21_20_00")
        let live = try LiveRead(url: url, session: session, resuming: saved, caughtUpAt: next.lines.count)
        let bookmark = try live.bookmark()
        #expect(bookmark.resumed?.gameSeed == saved.gameSeed)
        #expect(bookmark.shown.state.game?.lobby.first { $0.playerID == 3 }?.lastSeenBoard != nil)

        #expect(try TavernEngine.replay(bookmark, powerLog: url).timeline.last == bookmark.shown)
        // Without the carried record the moment can't be rebuilt.
        engine = try TavernEngine.replay(bookmark.cut, powerLog: url)
        #expect(engine.state != bookmark.shown.state)
    }

    // MARK: - Stored in the game's record

    @Test("A bookmark is saved in its game's record and survives the log being read again")
    func storedInRecord() throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GameRecordStore(directory: directory)
        let (url, session) = try Self.twoGames().write()

        var live = try LiveRead(url: url, session: session, caughtUpAt: 80)
        live.follow(through: live.lines.count)
        var bookmark = try live.bookmark(note: "gold looks off")
        let added = live.engine.addBookmark(bookmark)
        #expect(added)
        for record in live.engine.takeUnsavedRecords() { try store.save(record) }
        #expect(store.load(seed: 42)?.bookmarks == [bookmark])

        // A later read of the same log (the app restarted) knows nothing of the bookmark.
        var reread = try LiveRead(url: url, session: session, caughtUpAt: live.lines.count)
        _ = reread.engine.inProgressRecord
        for record in reread.engine.records { try store.save(record) }
        #expect(store.load(seed: 42)?.bookmarks == [bookmark])

        // Editing the note replaces it; a second one is added in time order.
        bookmark.note = "gold is right, tier is off"
        #expect(try store.add(bookmark))
        var second = try reread.bookmark(note: "second")
        second.createdAt = bookmark.createdAt.addingTimeInterval(5)
        #expect(try store.add(second))
        #expect(store.load(seed: 42)?.bookmarks.map(\.note) == ["gold is right, tier is off", "second"])
        #expect(store.allBookmarks().map(\.bookmark.id) == [second.id, bookmark.id])

        // An unknown game can't take a bookmark.
        var stray = bookmark
        stray.cut.gameSeed = 999
        #expect(try !store.add(stray))
        let strayAdded = reread.engine.addBookmark(stray)
        #expect(!strayAdded)
    }

    @Test("A game carried into the next session keeps its bookmarks")
    func carriedBookmarks() throws {
        let first = GameRecordTests.afterFirstCombat()
        var engine = GameRecordTests.replay(first.lines, session: try GameRecordTests.session("Hearthstone_2026_09_22_21_08_40"))
        let bookmark = try #require(engine.bookmark(note: "before the restart"))
        let added = engine.addBookmark(bookmark)
        #expect(added)
        let saved = try #require(engine.inProgressRecord)
        #expect(saved.bookmarks == [bookmark])

        var next = SyntheticLog()
        next.reconnect(turn: 3)
        engine = GameRecordTests.replay(next.lines, session: try GameRecordTests.session("Hearthstone_2026_09_22_21_20_00"),
                                        resuming: saved)
        #expect(engine.records.only?.bookmarks == [bookmark])
        #expect(engine.resumedRecord?.bookmarks == [])
    }

    @Test("Records written before bookmarks existed still load")
    func oldRecordsLoad() throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GameRecordStore(directory: directory)
        let record = try #require(GameRecordTests.replay(Self.twoGames().lines).records.last)
        try store.save(record)
        let url = store.url(for: record)
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json["bookmarks"] = nil
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        #expect(store.load(seed: 42)?.summary == record.summary)
        #expect(store.load(seed: 42)?.bookmarks == [])
    }

    @Test("No bookmark before a game is shown or during catch-up")
    func noBookmarkWithoutGame() throws {
        var engine = TavernEngine()
        #expect(engine.bookmark() == nil)
        engine.beginCatchUp()
        for line in Self.twoGames().lines { engine.ingest(line) }
        #expect(engine.bookmark() == nil)
        engine.endCatchUp()
        #expect(engine.bookmark() != nil)
    }

    // MARK: - Golden cases

    @Test("Export writes a redacted case and the log stretch it replays, into a checkout's layout")
    func export() throws {
        let root = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (url, session) = try Self.twoGames().write()
        var live = try LiveRead(url: url, session: session, caughtUpAt: 70)
        live.follow(through: live.lines.count)
        let bookmark = try live.bookmark(note: "combat board looks right")
        #expect(bookmark.shown.state.game?.lobby.contains { $0.displayName == LobbySyntheticTests.opponentName } == true)

        let exported = try BookmarkExport.export(bookmark, powerLog: url, name: "Synthetic Case", into: root)
        #expect(exported.caseFile == root.appending(path: "Tests/TavernEngineTests/Golden/Bookmarks/synthetic-case.json"))
        #expect(exported.logFile == root.appending(path: "fixtures/private-logs/bookmarks/synthetic-case/Power.log"))

        // The log is only the cut's lines; the case replays from it.
        let copied = try String(contentsOf: exported.logFile, encoding: .utf8)
        let expectedLines = live.lines[(bookmark.cut.startLine - 1)..<bookmark.cut.endLine]
        #expect(copied == expectedLines.joined(separator: "\n") + "\n")
        let text = try String(contentsOf: exported.caseFile, encoding: .utf8)
        #expect(!text.contains(LobbySyntheticTests.opponentName))
        let loaded = try BookmarkGoldenCase.decode(Data(contentsOf: exported.caseFile))
        #expect(loaded == exported.goldenCase)
        #expect(loaded.note == "combat board looks right")
        #expect(loaded.expected == bookmark.shown.redactingNames())
        #expect(try loaded.replay(powerLog: exported.logFile) == loaded.expected)
        #expect(loaded.expected.state.game?.lobby.contains { $0.displayName == "Opp-P3" } == true)
    }

    @Test("Export refuses a note with a BattleTag and a log that's gone")
    func exportRefuses() throws {
        let root = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (url, _) = try Self.twoGames().write()
        let live = try LiveRead(url: url, caughtUpAt: 120)
        let tagged = try live.bookmark(note: "ask Tester#0042 about this")
        #expect(throws: BookmarkReplayError.containsBattleTag) {
            try BookmarkExport.export(tagged, powerLog: url, into: root)
        }
        #expect(throws: BookmarkReplayError.missingLog(root.appending(path: "nope.log").path(percentEncoded: false))) {
            try BookmarkExport.export(tagged, powerLog: root.appending(path: "nope.log"), into: root)
        }
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Tests").path(percentEncoded: false)))
    }

    @Test("A case whose log was cut short fails to replay instead of passing")
    func shortLogFails() throws {
        let (url, _) = try Self.twoGames().write()
        let live = try LiveRead(url: url, caughtUpAt: 120)
        var cut = try live.bookmark().cut
        cut.endLine = live.lines.count + 10
        #expect(throws: BookmarkReplayError.self) { try TavernEngine.replay(cut, powerLog: url) }
    }

    @Test("Default names are file-name safe")
    func defaultName() throws {
        let (url, _) = try Self.twoGames().write()
        let bookmark = try LiveRead(url: url, caughtUpAt: 120).bookmark()
        let name = BookmarkExport.defaultName(for: bookmark)
        #expect(name.hasPrefix("bookmark-42-t"))
        #expect(name.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" })
    }
}
