import Foundation
import HSLog
import Testing

/// Seam 3: cutting a Power.log into per-game slices, and compressing them.
@Suite("Per-game log slices")
struct PowerLogGamesTests {
    static func createGame(seed: Int?) -> [String] {
        var lines = [
            "D 21:00:00.0000000 GameState.DebugPrintPowerList() - Count=44",
            "D 21:00:00.0000000 GameState.DebugPrintPower() - CREATE_GAME",
            "D 21:00:00.0000000 GameState.DebugPrintPower() -     GameEntity EntityID=16",
        ]
        if let seed { lines.append("D 21:00:00.0000000 GameState.DebugPrintPower() -         tag=GAME_SEED value=\(seed)") }
        lines.append("D 21:00:00.0000000 PowerTaskList.DebugPrintPower() -     CREATE_GAME")
        return lines
    }

    static func body(_ tag: String, lines count: Int) -> [String] {
        (0..<count).map { "D 21:00:01.0000000 PowerTaskList.DebugPrintPower() -     TAG_CHANGE Entity=GameEntity tag=\(tag) value=\($0) " }
    }

    static func text(_ lines: [String]) -> Data { Data((lines.joined(separator: "\n") + "\n").utf8) }

    static func lines(_ data: Data) -> [String] {
        var splitter = LogLineSplitter()
        var result: [String] = []
        splitter.append(data) { result.append($0) }
        if let last = splitter.finish() { result.append(last) }
        return result
    }

    @Test("Each game is a slice from its CREATE_GAME line; a same-seed reconnect stays in its game")
    func slices() throws {
        let preamble = ["D 20:59:00.0000000 PowerTaskList.DebugPrintPower() - junk before any game"]
        let first = Self.createGame(seed: 11) + Self.body("TURN", lines: 3)
        let reconnect = Self.createGame(seed: 11) + Self.body("TURN", lines: 2)
        let second = Self.createGame(seed: 22) + Self.body("STEP", lines: 4)
        let unseeded = Self.createGame(seed: nil) + Self.body("STEP", lines: 1)
        let all = preamble + first + reconnect + second + unseeded
        let data = Self.text(all)

        let slices = PowerLogGames.slices(in: data)
        #expect(slices.map(\.gameSeed) == [11, 22, nil])
        // Slices start at the CREATE_GAME line itself (the line before it is part of the previous slice).
        #expect(slices.map(\.line) == [3, 3 + first.count + reconnect.count, 3 + first.count + reconnect.count + second.count])
        for slice in slices {
            #expect(Self.lines(data.subdata(in: slice.byteRange)).first == all[slice.line - 1])
        }
        #expect(slices.last?.byteRange.upperBound == data.count)
        // The slices are contiguous and each holds its game's lines.
        #expect(zip(slices, slices.dropFirst()).allSatisfy { $0.byteRange.upperBound == $1.byteRange.lowerBound })
        let firstLines = Self.lines(data.subdata(in: slices[0].byteRange))
        #expect(firstLines == Array(all[2..<(2 + first.count + reconnect.count)]))
    }

    @Test("A log with no game has no slices")
    func noGames() {
        #expect(PowerLogGames.slices(in: Self.text(Self.body("TURN", lines: 5))).isEmpty)
        #expect(PowerLogGames.slices(in: Data()).isEmpty)
        #expect(PowerLogGames.slices(in: URL(filePath: "/nonexistent/Power.log")).isEmpty)
    }

    @Test("gzip round-trips and compresses log text")
    func gzip() throws {
        let data = Self.text((0..<2000).flatMap { _ in Self.createGame(seed: 1_172_082_863) + Self.body("TURN", lines: 20) })
        let compressed = try Gzip.compress(data)
        #expect(compressed.prefix(2) == Data([0x1F, 0x8B]))
        #expect(compressed.count * 10 < data.count)
        #expect(try Gzip.decompress(compressed) == data)
        #expect(try Gzip.decompress(Gzip.compress(Data())) == Data())
        #expect(throws: Gzip.Failure.truncated) { try Gzip.decompress(compressed.prefix(compressed.count / 2)) }
    }

    @Test("A real game's slice is the whole game, and compresses about 10×", .enabled(if: Self.fullGame != nil))
    func fixtureSlice() throws {
        let url = try #require(Self.fullGame)
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        let slice = try #require(PowerLogGames.slices(in: data).only)
        #expect(slice.line == 2)
        #expect(slice.gameSeed != nil)
        #expect(slice.byteRange.upperBound == data.count)
        let compressed = try Gzip.compress(data.subdata(in: slice.byteRange))
        #expect(compressed.count * 8 < slice.byteRange.count)
    }

    static let fullGame: URL? = {
        // TAVERN_FIXTURES_DIR, else the nearest fixtures/private-logs above this file (also from a worktree).
        let game = "Hearthstone_2026_09_22_21_08_40/Power.log"
        var candidates: [URL] = []
        if let override = ProcessInfo.processInfo.environment["TAVERN_FIXTURES_DIR"] {
            candidates = [URL(filePath: override)]
        } else {
            var dir = URL(filePath: #filePath).deletingLastPathComponent()
            while dir.pathComponents.count > 1 {
                candidates.append(dir.appending(path: "fixtures/private-logs"))
                dir = dir.deletingLastPathComponent()
            }
        }
        return candidates.map { $0.appending(path: game) }
            .first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }()
}

private extension Collection {
    var only: Element? { count == 1 ? first : nil }
}
