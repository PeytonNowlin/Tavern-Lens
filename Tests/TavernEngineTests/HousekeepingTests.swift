import Foundation
import HSLog
import Testing
import TavernEngine

/// Seam 3 with the engine: a housekeeping pass over a temporary `Logs/` tree, with
/// temporary record and replay stores. Games a session holds are recorded (and saved
/// as replays) before its folder goes; replays replay exactly like the original log.
@Suite("Log housekeeping: records, replays and pruning")
struct HousekeepingTests {
    static let utc = TimeZone(identifier: "UTC")!

    /// A temporary Logs tree plus the app's stores, removed on deinit.
    final class Sandbox {
        let root: URL
        let logs: URL
        let records: GameRecordStore
        let replays: ReplayStore

        init() throws {
            root = FileManager.default.temporaryDirectory.appending(path: "TavernLensHousekeeping-\(UUID().uuidString)")
            logs = root.appending(path: "Applications/Hearthstone/Logs", directoryHint: .isDirectory)
            records = GameRecordStore(directory: root.appending(path: "Support/Games"))
            replays = ReplayStore(directory: root.appending(path: "Support/Replays"))
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        var housekeeper: LogHousekeeper {
            LogHousekeeper(logsDirectory: logs, records: records, replays: replays, timeZone: HousekeepingTests.utc)
        }

        /// Writes a session folder whose Power.log holds `lines`.
        @discardableResult
        func session(_ name: String, _ lines: [String]) throws -> LogSession {
            let folder = logs.appending(path: name, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: folder.appending(path: LogFileName.power))
            return try #require(LogSession(directory: folder, timeZone: HousekeepingTests.utc))
        }

        /// A record as it reads back from disk (dates keep milliseconds only).
        func onDisk(_ record: GameRecord) throws -> GameRecord {
            let store = GameRecordStore(directory: root.appending(path: "RoundTrip-\(UUID().uuidString)"))
            try store.save(record)
            let seed = try #require(record.gameSeed)
            return try #require(store.load(seed: seed))
        }

        var sessionNames: [String] { LogSessionDiscovery.sessions(in: logs, timeZone: HousekeepingTests.utc).map(\.name) }
    }

    static func name(day: Int) -> String { String(format: "Hearthstone_2026_09_%02d_20_00_00", day) }

    /// A solo BG game with `seed`, finished unless `complete` is false.
    static func game(seed: Int, turns: Int = 2, complete: Bool = true) -> [String] {
        var log = SyntheticLog()
        log.createGame(gameType: "GT_BATTLEGROUNDS", seed: seed)
        log.pickHero()
        log.playTurns(turns)
        if complete { log.completeGame() }
        return log.lines
    }

    /// A ranked game: in the log, but never recorded.
    static func rankedGame(seed: Int) -> [String] {
        var log = SyntheticLog()
        log.createGame(gameType: "GT_RANKED", seed: seed)
        log.turn(1)
        return log.lines
    }

    static func settings(sessions: Int, replays: Int = 40, keepReplays: Bool = true) -> RetentionSettings {
        var settings = RetentionSettings()
        settings.maxSessions = sessions
        settings.maxReplays = replays
        settings.keepReplays = keepReplays
        return settings
    }

    // MARK: - Recording before pruning

    @Test("Games the app never saw are recorded before their folder is pruned, and saved as replays")
    func importsBeforePruning() throws {
        let box = try Sandbox()
        let first = try box.session(Self.name(day: 1), Self.game(seed: 10) + Self.rankedGame(seed: 99) + Self.game(seed: 11, complete: false))
        try box.session(Self.name(day: 2), Self.game(seed: 20))
        try box.session(Self.name(day: 3), Self.game(seed: 30))
        let expected = try TavernEngine.replay(fileAt: first.powerLog, session: first, timeZone: Self.utc)

        let report = box.housekeeper.run(settings: Self.settings(sessions: 1))

        #expect(report.logs.deleted == [Self.name(day: 1), Self.name(day: 2)])
        #expect(box.sessionNames == [Self.name(day: 3)])
        #expect(report.importedSessions == [Self.name(day: 1), Self.name(day: 2)])
        #expect(report.importedRecords == 3)
        // Every BG game has its record: the first session's two (one unfinished) and the second's.
        #expect(try box.records.load(seed: 10) == box.onDisk(expected.records[0]))
        #expect(try box.records.load(seed: 11) == box.onDisk(expected.records[1]))
        #expect(box.records.load(seed: 11)?.outcome == .inProgress)
        #expect(box.records.load(seed: 20)?.outcome == .complete)
        #expect(box.records.load(seed: 99) == nil)
        // The newest session's game isn't recorded yet (the live pipeline does that), so it has no replay.
        #expect(box.records.load(seed: 30) == nil)
        #expect(box.replays.all(timeZone: Self.utc).map(\.gameSeed) == [10, 11, 20])
        #expect(report.replaysSaved.map(\.gameSeed) == [10, 11, 20])
    }

    @Test("A replay replays identically to the original log: timeline, records and line numbers")
    func replayIsIdentical() throws {
        let box = try Sandbox()
        let lines = Self.game(seed: 10) + Self.rankedGame(seed: 99) + Self.game(seed: 11, turns: 3)
        let session = try box.session(Self.name(day: 1), lines)
        try box.session(Self.name(day: 2), [])
        let full = try TavernEngine.replay(fileAt: session.powerLog, session: session, timeZone: Self.utc)
        box.housekeeper.run(settings: Self.settings(sessions: 1))

        let replays = box.replays.all(timeZone: Self.utc)
        #expect(replays.map(\.gameSeed) == [10, 11])
        // Slice boundaries in the original: game 10, the ranked game, game 11.
        let starts = PowerLogGames.slices(in: Data((lines.joined(separator: "\n") + "\n").utf8)).map(\.line)
        #expect(starts.count == 3)
        for (index, replay) in replays.enumerated() {
            #expect(replay.sessionName == session.name)
            let replayed = try TavernEngine.replay(replay, timeZone: Self.utc)
            #expect(replayed.records == [full.records[index]])
            // The game's stretch of the full timeline, with the same line numbers.
            let end = starts.first { $0 > replay.line } ?? Int.max
            let original = full.timeline.filter { $0.position.line >= replay.line && $0.position.line < end }
            #expect(!original.isEmpty)
            #expect(replayed.timeline == original)
        }
    }

    @Test("A folder whose games can't be recorded is kept; the next one goes instead")
    func unrecordableIsKept() throws {
        let box = try Sandbox()
        try box.session(Self.name(day: 1), Self.game(seed: 10))
        try box.session(Self.name(day: 2), Self.rankedGame(seed: 98))
        try box.session(Self.name(day: 3), [])
        try box.session(Self.name(day: 4), Self.game(seed: 40))
        // The record store can't be written: its directory is a file.
        try FileManager.default.createDirectory(at: box.records.directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a folder".utf8).write(to: box.records.directory)

        let report = box.housekeeper.run(settings: Self.settings(sessions: 1))
        #expect(report.logs.kept[Self.name(day: 1)] == .unrecorded)
        // No BG games in these, so nothing to record.
        #expect(report.logs.deleted == [Self.name(day: 2), Self.name(day: 3)])
        #expect(box.sessionNames == [Self.name(day: 1), Self.name(day: 4)])
        #expect(box.replays.all().isEmpty)
    }

    @Test("A folder whose games are already recorded isn't read again")
    func alreadyRecorded() throws {
        let box = try Sandbox()
        let first = try box.session(Self.name(day: 1), Self.game(seed: 10))
        try box.session(Self.name(day: 2), [])
        let live = try TavernEngine.replay(fileAt: first.powerLog, session: first, timeZone: Self.utc)
        var saved = try #require(live.records.first)
        saved.journal.displayNames[3] = "Marker"  // not in the log: an import would overwrite it
        try box.records.save(saved)

        let report = box.housekeeper.run(settings: Self.settings(sessions: 1, keepReplays: false))
        #expect(report.logs.deleted == [Self.name(day: 1)])
        #expect(report.importedRecords == 0)
        #expect(try box.records.load(seed: 10) == box.onDisk(saved))
        #expect(box.replays.all().isEmpty)
    }

    @Test("The active session is never pruned, even over every limit")
    func activeIsKept() throws {
        let box = try Sandbox()
        for day in 1...4 { try box.session(Self.name(day: day), Self.game(seed: day)) }
        let report = box.housekeeper.run(settings: Self.settings(sessions: 0), activeSessions: [Self.name(day: 2)])
        #expect(report.logs.deleted == [Self.name(day: 1), Self.name(day: 3)])
        #expect(report.logs.kept == [Self.name(day: 2): .active, Self.name(day: 4): .newest])
        #expect(box.sessionNames == [Self.name(day: 2), Self.name(day: 4)])
    }

    // MARK: - Replays of the live session

    @Test("After a game ends, its slice of the live Power.log is saved once; a game still going isn't")
    func liveSessionReplays() throws {
        let box = try Sandbox()
        let lines = Self.game(seed: 10) + Self.game(seed: 11, complete: false)
        let session = try box.session(Self.name(day: 1), lines)
        // What the live pipeline saved as the games went on.
        for record in try TavernEngine.replay(fileAt: session.powerLog, session: session, timeZone: Self.utc).records {
            try box.records.save(record)
        }

        let first = box.housekeeper.run(settings: Self.settings(sessions: 10))
        #expect(first.replaysSaved.map(\.gameSeed) == [10])
        #expect(first.logs.deleted.isEmpty)
        #expect(box.housekeeper.run(settings: Self.settings(sessions: 10)).replaysSaved.isEmpty)
        #expect(box.housekeeper.run(settings: Self.settings(sessions: 10, keepReplays: false)).replaysSaved.isEmpty)
    }

    // MARK: - Settings

    @Test("Settings changes take effect on the next pass")
    func settingsApplyNextPass() throws {
        let box = try Sandbox()
        for day in 1...6 { try box.session(Self.name(day: day), Self.game(seed: day)) }

        let first = box.housekeeper.run(settings: Self.settings(sessions: 10))
        #expect(first.logs.deleted.isEmpty && box.replays.all().isEmpty)

        let second = box.housekeeper.run(settings: Self.settings(sessions: 3, keepReplays: false))
        #expect(second.logs.deleted == (1...3).map { Self.name(day: $0) })
        #expect(box.replays.all().isEmpty)
        #expect((1...3).allSatisfy { box.records.load(seed: $0) != nil })

        var bySize = Self.settings(sessions: 3, replays: 1)
        bySize.maxLogBytes = LogRetention.directorySize(box.logs.appending(path: Self.name(day: 6))) + 1
        let third = box.housekeeper.run(settings: bySize)
        #expect(third.logs.deleted == [Self.name(day: 4), Self.name(day: 5)])
        #expect(third.replaysSaved.map(\.gameSeed) == [4, 5])
        #expect(third.replaysDeleted.map(\.gameSeed) == [4])
        #expect(box.replays.all(timeZone: Self.utc).map(\.gameSeed) == [5])

        let fourth = box.housekeeper.run(settings: Self.settings(sessions: 3, replays: 0))
        #expect(fourth.replaysDeleted.map(\.gameSeed) == [5])
        #expect(box.replays.all().isEmpty)
    }

    @Test("The replay cap keeps the newest games")
    func replayCap() throws {
        let box = try Sandbox()
        for day in 1...5 { try box.session(Self.name(day: day), Self.game(seed: day * 10) + Self.game(seed: day * 10 + 1)) }
        let report = box.housekeeper.run(settings: Self.settings(sessions: 1, replays: 3))
        #expect(report.replaysSaved.count == 8)
        #expect(box.replays.all(timeZone: Self.utc).map(\.gameSeed) == [31, 40, 41])
    }

    @Test("Settings saved without newer keys decode with defaults")
    func settingsDecoding() throws {
        let decoded = try JSONDecoder().decode(RetentionSettings.self, from: Data(#"{"maxSessions": 4}"#.utf8))
        var expected = RetentionSettings()
        expected.maxSessions = 4
        #expect(decoded == expected)
        #expect(RetentionSettings().maxLogBytes == 2_000_000_000)
        #expect(RetentionSettings().maxReplays == 40)
        #expect(RetentionSettings().powerLogHintBytes == 800_000_000)
        #expect(RetentionSettings().maxArtCacheBytes == 1_000_000_000)
    }

    // MARK: - Captured log

    @Test(
        "A captured game's replay is a tenth of its log and replays identically",
        .enabled(if: Fixtures.isAvailable(Fixtures.fullGame), "private fixture log not present")
    )
    func capturedReplay() throws {
        let url = try #require(Fixtures.url(Fixtures.fullGame))
        let session = try #require(LogSession(directory: url.deletingLastPathComponent(), timeZone: Self.utc))
        let box = try Sandbox()
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        let slice = try #require(PowerLogGames.slices(in: data).first)
        let replay = try box.replays.save(slice, of: data, sessionName: session.name)
        let size = try #require(try replay.url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        #expect(size * 8 < data.count, "replay is \(size) bytes")

        let original = try TavernEngine.replay(fileAt: url, session: session, timeZone: Self.utc)
        let replayed = try TavernEngine.replay(replay, timeZone: Self.utc)
        #expect(replayed.timeline == original.timeline)
        #expect(replayed.records == original.records)
        #expect(replayed.diagnostics.linesRead == original.diagnostics.linesRead)
    }
}
