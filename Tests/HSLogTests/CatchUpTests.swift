import Foundation
import HSLog
import Testing

/// Seam 3: dating log lines from the session folder, and finding where to start reading
/// a Power.log to rebuild the game in progress.
@Suite("Log dates and catch-up entry point", .serialized)
struct CatchUpTests {
    static let utc = TimeZone(identifier: "UTC")!

    static func clock(_ folder: String) throws -> LogClock {
        let session = try #require(LogSession(directory: URL(filePath: "/tmp/Logs/\(folder)"), timeZone: utc))
        return LogClock(session: session, timeZone: utc)
    }

    static func iso(_ date: Date?) -> String? {
        date.map { $0.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: utc)) }
    }

    // MARK: - Dates

    @Test("Times of day are dated from the session folder, and the next day after midnight")
    func midnightRollover() throws {
        var clock = try Self.clock("Hearthstone_2026_09_22_21_08_40")
        #expect(Self.iso(clock.date(for: "21:09:40.3435500")) == "2026-09-22T21:09:40.343Z")
        #expect(Self.iso(clock.date(for: "23:59:59.9872550")) == "2026-09-22T23:59:59.987Z")
        #expect(Self.iso(clock.date(for: "00:00:01.8490680")) == "2026-09-23T00:00:01.849Z")
        #expect(Self.iso(clock.date(for: "13:00:00.0000000")) == "2026-09-23T13:00:00.000Z")
        // A second midnight (a very long session).
        #expect(Self.iso(clock.date(for: "00:30:00.0000000")) == "2026-09-24T00:30:00.000Z")
        #expect(clock.dayOffset == 2)
    }

    @Test("A session started just before midnight whose first line is after it is the next day")
    func folderBeforeMidnight() throws {
        var clock = try Self.clock("Hearthstone_2026_12_31_23_59_58")
        #expect(Self.iso(clock.date(for: "00:00:01.0000000")) == "2027-01-01T00:00:01.000Z")
    }

    @Test("A small step back (a clock change) is clamped, never read as a new day")
    func smallBackwardStep() throws {
        var clock = try Self.clock("Hearthstone_2026_09_22_21_08_40")
        _ = clock.date(for: "22:30:00.0000000")
        #expect(Self.iso(clock.date(for: "21:30:00.0000000")) == "2026-09-22T22:30:00.000Z")
        #expect(Self.iso(clock.date(for: "22:31:00.0000000")) == "2026-09-22T22:31:00.000Z")
        #expect(clock.dayOffset == 0)
    }

    @Test("Text that isn't a time of day leaves the clock alone")
    func notATimestamp() throws {
        var clock = try Self.clock("Hearthstone_2026_09_22_21_08_40")
        for text in ["", "21:08", "25:00:00.0", "21:08:40.1.2", "ab:cd:ef", "==="] {
            #expect(clock.date(for: text) == nil, "\(text)")
        }
        #expect(Self.iso(clock.currentDate) == "2026-09-22T21:08:40.000Z")
        #expect(Self.iso(clock.date(for: "21:08:41")) == "2026-09-22T21:08:41.000Z")
    }

    // MARK: - Entry point

    /// One game's opening in the real shape: GameState's `CREATE_GAME` (with the seed a few
    /// lines in), `DebugPrintGame`, then the synced `CREATE_GAME`.
    static func game(seed: Int, turns: Int = 3) -> [String] {
        var lines = [
            "D 21:09:40.3435500 GameState.DebugPrintPowerList() - Count=44",
            "D 21:09:40.3435500 GameState.DebugPrintPower() - CREATE_GAME",
            "D 21:09:40.3435500 GameState.DebugPrintPower() -     GameEntity EntityID=16",
            "D 21:09:40.3435500 GameState.DebugPrintPower() -         tag=GAME_SEED value=\(seed)",
            "D 21:09:40.3435500 GameState.DebugPrintGame() - GameType=GT_BATTLEGROUNDS",
            "D 21:09:40.3435500 PowerTaskList.DebugPrintPower() -     CREATE_GAME",
            "D 21:09:40.3435500 PowerTaskList.DebugPrintPower() -         tag=GAME_SEED value=\(seed)",
        ]
        for turn in 1...turns {
            lines.append("D 21:10:00.0000000 PowerTaskList.DebugPrintPower() -     TAG_CHANGE Entity=GameEntity tag=TURN value=\(turn) ")
        }
        return lines
    }

    static func entry(_ lines: [String]) -> PowerLogEntryPoint? {
        PowerLogEntryPoint.find(in: Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    /// The byte offset of line `n` (1-based).
    static func offset(ofLine n: Int, in lines: [String]) -> UInt64 {
        UInt64(lines.prefix(n - 1).reduce(0) { $0 + $1.utf8.count + 1 })
    }

    @Test("A log with no game has no entry point")
    func noGame() {
        #expect(Self.entry([]) == nil)
        #expect(Self.entry(["D 21:08:40.0 LoadingScreen.OnSceneLoaded() - prevMode=STARTUP currMode=LOGIN"]) == nil)
    }

    @Test("One game: its GameState CREATE_GAME line")
    func oneGame() throws {
        let lines = Self.game(seed: 11)
        let entry = try #require(Self.entry(lines))
        #expect(entry == PowerLogEntryPoint(byteOffset: Self.offset(ofLine: 2, in: lines), line: 2, gameSeed: 11))
    }

    @Test("Several games: the latest one")
    func latestGame() throws {
        let lines = Self.game(seed: 11) + Self.game(seed: 22) + Self.game(seed: 33)
        let entry = try #require(Self.entry(lines))
        let line = 2 * Self.game(seed: 0).count + 2
        #expect(entry == PowerLogEntryPoint(byteOffset: Self.offset(ofLine: line, in: lines), line: line, gameSeed: 33))
        #expect(lines[line - 1].hasSuffix("GameState.DebugPrintPower() - CREATE_GAME"))
    }

    @Test("A reconnect in the same log: the first CREATE_GAME of the latest seed, so its history is replayed")
    func reconnectInFile() throws {
        let lines = Self.game(seed: 11) + Self.game(seed: 22) + Self.game(seed: 22) + Self.game(seed: 22)
        let entry = try #require(Self.entry(lines))
        let line = Self.game(seed: 0).count + 2
        #expect(entry.line == line)
        #expect(entry.byteOffset == Self.offset(ofLine: line, in: lines))
        #expect(entry.gameSeed == 22)
    }

    @Test("A game whose seed isn't printed yet (the file ends mid-block) is still the entry")
    func seedNotYetWritten() throws {
        let lines = Self.game(seed: 11) + Array(Self.game(seed: 22).prefix(3))
        let entry = try #require(Self.entry(lines))
        #expect(entry.line == Self.game(seed: 0).count + 2)
        #expect(entry.gameSeed == nil)
    }

    @Test("Captured logs: the entry point of a 36 MB log is found in well under a second")
    func capturedLog() throws {
        let override = ProcessInfo.processInfo.environment["TAVERN_FIXTURES_DIR"].map { URL(filePath: $0) }
        let candidates = override.map { [$0] }
            ?? Self.ancestors(of: URL(filePath: #filePath)).map { $0.appending(path: "fixtures/private-logs") }
        let game = "Hearthstone_2026_09_22_21_08_40/Power.log"
        guard let directory = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0.appending(path: game).path(percentEncoded: false))
        }) else { return }  // private fixtures absent
        let url = directory.appending(path: game)
        let clock = ContinuousClock()
        var entry: PowerLogEntryPoint?
        let elapsed = clock.measure { entry = PowerLogEntryPoint.find(in: url) }
        #expect(entry?.line == 2)
        #expect(entry?.byteOffset == UInt64("D 21:09:40.3435500 GameState.DebugPrintPowerList() - Count=44\n".utf8.count))
        #expect(entry?.gameSeed != nil)
        #expect(elapsed < .milliseconds(500), "entry point took \(elapsed)")
    }

    static func ancestors(of url: URL) -> [URL] {
        var result: [URL] = []
        var dir = url.deletingLastPathComponent()
        while dir.pathComponents.count > 1 {
            result.append(dir)
            dir = dir.deletingLastPathComponent()
        }
        return result
    }

    // MARK: - Following from the entry point

    @Test("Joining a session reads Power.log from its latest game, then says when it has caught up")
    func followFromEntryPoint() async throws {
        let install = try TemporaryInstall()
        let session = try install.makeSession("Hearthstone_2026_09_22_21_08_40")
        let power = session.appending(path: LogFileName.power)
        let old = Self.game(seed: 11)
        let current = Self.game(seed: 22)
        try install.append((old + current).joined(separator: "\n") + "\n", to: power)

        let recorder = EventRecorder()
        let follower = LogSessionFollower(
            logsDirectory: install.locations.logsDirectory, fileNames: [LogFileName.power],
            startsAtLatestGame: true, timeZone: Self.utc, handler: { recorder.record($0) }
        )
        follower.start()
        defer { follower.stop() }

        #expect(await recorder.wait { $0.caughtUp.contains(LogFileName.power) })
        #expect(recorder.lines(of: LogFileName.power) == Array(current.dropFirst()))
        #expect(recorder.entries.map(\.line) == [old.count + 2])

        let live = "D 21:11:00.0000000 PowerTaskList.DebugPrintPower() -     TAG_CHANGE Entity=GameEntity tag=TURN value=4 "
        try install.append(live + "\n", to: power)
        #expect(await recorder.wait { $0.lines(of: LogFileName.power).last == live })
        #expect(recorder.caughtUp == [LogFileName.power])
    }
}
