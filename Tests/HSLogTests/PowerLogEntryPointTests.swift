import Foundation
import HSLog
import Testing

/// The entry point is the latest game's slice; reads of the live file never memory-map it.
@Suite("Power.log entry point and live reads")
struct PowerLogEntryPointTests {
    typealias Fixture = PowerLogGamesTests

    static func log() -> (all: [String], data: Data, firstTwo: Int) {
        let preamble = ["D 20:59:00.0000000 PowerTaskList.DebugPrintPower() - junk before any game"]
        let first = Fixture.createGame(seed: 11) + Fixture.body("TURN", lines: 3)
        let reconnect = Fixture.createGame(seed: 11) + Fixture.body("TURN", lines: 2)
        let second = Fixture.createGame(seed: 22) + Fixture.body("STEP", lines: 4)
        let all = preamble + first + reconnect + second
        return (all, Fixture.text(all), preamble.count + first.count + reconnect.count)
    }

    @Test("find equals the last slice's start, for every prefix of a log with a reconnect")
    func equivalence() {
        let (all, data, _) = Self.log()
        // Cut after each line so the latest game is each of: none, seed 11, 11 + reconnect, seed 22.
        for count in 0...all.count {
            let prefix = Fixture.text(Array(all[0..<count]))
            let slice = PowerLogGames.slices(in: count == 0 ? Data() : prefix).last
            let entry = PowerLogEntryPoint.find(in: count == 0 ? Data() : prefix)
            #expect(entry?.line == slice?.line)
            #expect(entry?.byteOffset == slice.map { UInt64($0.byteRange.lowerBound) })
            #expect(entry?.gameSeed == slice?.gameSeed)
        }
        let entry = PowerLogEntryPoint.find(in: data)
        #expect(entry?.gameSeed == 22)
        // The CREATE_GAME line follows the Count= line of its block.
        #expect(entry?.line == Self.log().firstTwo + 2)
    }

    @Test("A same-seed reconnect is walked back to the first CREATE_GAME of that game")
    func reconnectEntry() {
        let preamble = ["D 20:59:00.0000000 PowerTaskList.DebugPrintPower() - junk"]
        let first = Fixture.createGame(seed: 5) + Fixture.body("TURN", lines: 2)
        let reconnect = Fixture.createGame(seed: 5) + Fixture.body("TURN", lines: 2)
        let all = preamble + first + reconnect
        let entry = PowerLogEntryPoint.find(in: Fixture.text(all))
        #expect(entry?.gameSeed == 5)
        #expect(entry?.line == 3)
        let data = Fixture.text(all)
        let start = Int(entry?.byteOffset ?? 0)
        #expect(Fixture.lines(data.subdata(in: start..<data.count)).first == all[2])
    }

    @Test("A log with no game has no entry point")
    func none() {
        #expect(PowerLogEntryPoint.find(in: Data()) == nil)
        #expect(PowerLogEntryPoint.find(in: Fixture.text(Fixture.body("TURN", lines: 3))) == nil)
    }

    @Test("The file-based readers agree with the byte-based ones")
    func fileMatchesBytes() throws {
        let (_, data, _) = Self.log()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("entry-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        #expect(PowerLogEntryPoint.find(in: url) == PowerLogEntryPoint.find(in: data))
        #expect(PowerLogGames.slices(in: url) == PowerLogGames.slices(in: data))
        #expect(LogLineOffsets.end(ofLine: 3, in: url) == LogLineOffsets.end(ofLine: 3, in: data))
    }

    @Test("Truncating the file between reads, or while reading, does not crash")
    func truncation() async throws {
        let (_, data, _) = Self.log()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("trunc-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        #expect(PowerLogEntryPoint.find(in: url) != nil)

        // Shrink while a reader loops: with a memory mapping this is a SIGBUS.
        let handle = try FileHandle(forWritingTo: url)
        let reader = Task.detached {
            for _ in 0..<200 {
                _ = PowerLogEntryPoint.find(in: url)
                _ = PowerLogGames.slices(in: url)
                _ = LogLineOffsets.end(ofLine: 5, in: url)
            }
        }
        for _ in 0..<50 {
            try handle.truncate(atOffset: 0)
            try handle.seek(toOffset: 0)
            try handle.write(contentsOf: data)
            try handle.truncate(atOffset: UInt64(data.count / 3))
        }
        await reader.value
        try handle.truncate(atOffset: 0)
        try handle.close()
        #expect(PowerLogEntryPoint.find(in: url) == nil)
        #expect(PowerLogGames.slices(in: url).isEmpty)
        #expect(LogLineOffsets.end(ofLine: 1, in: url) == nil)
    }
}
