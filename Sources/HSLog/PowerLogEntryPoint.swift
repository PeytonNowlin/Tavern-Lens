import Darwin
import Foundation

/// Where to start reading a Power.log to rebuild the game in progress (log-edge-cases §7).
///
/// A session's Power.log holds every game of that client launch. Only the latest game
/// matters when joining late, so reading starts at its `GameState` `CREATE_GAME` line.
/// A reconnect inside the same file resends `CREATE_GAME` with the same `GAME_SEED`, so
/// the entry walks back over consecutive games with the latest game's seed and starts
/// at the first of them: the history before the reconnect is replayed too.
///
/// The search works on the raw bytes (memory-mapped), so finding the entry in a large
/// log takes milliseconds; the lines before it are never parsed.
public struct PowerLogEntryPoint: Hashable, Sendable {
    /// Byte offset of the start of the entry line.
    public var byteOffset: UInt64
    /// The entry line's 1-based line number in the file.
    public var line: Int
    /// `GAME_SEED` of the game read from here, when the `CREATE_GAME` block had one.
    public var gameSeed: Int?

    public init(byteOffset: UInt64, line: Int, gameSeed: Int?) {
        self.byteOffset = byteOffset
        self.line = line
        self.gameSeed = gameSeed
    }

    static let createGame = Array("GameState.DebugPrintPower() - CREATE_GAME".utf8)
    static let seedTag = Array("tag=GAME_SEED value=".utf8)
    /// The seed is on the game entity, a few lines into the block; never look further than this.
    static let seedSearchLimit = 64 * 1024

    /// The entry point of the file at `url`; nil when it has no game (or can't be read).
    public static func find(in url: URL) -> PowerLogEntryPoint? {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        return find(in: data)
    }

    /// The entry point of a log's bytes; nil when it has no game.
    public static func find(in data: Data) -> PowerLogEntryPoint? {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> PowerLogEntryPoint? in
            guard let base = raw.baseAddress, !raw.isEmpty else { return nil }
            let starts = occurrences(of: createGame, in: base, count: raw.count)
            guard !starts.isEmpty else { return nil }
            var games = starts.indices.map { index -> (offset: Int, seed: Int?) in
                let end = index + 1 < starts.count ? starts[index + 1] : raw.count
                return (starts[index], seed(in: base, from: starts[index], to: min(end, starts[index] + seedSearchLimit)))
            }
            var entry = games.removeLast()
            if let seed = entry.seed {
                while let previous = games.last, previous.seed == seed {
                    entry = games.removeLast()
                }
            }
            let lineStart = startOfLine(containing: entry.offset, in: base)
            return PowerLogEntryPoint(
                byteOffset: UInt64(lineStart),
                line: newlines(in: base, count: lineStart) + 1,
                gameSeed: entry.seed
            )
        }
    }

    static func occurrences(of needle: [UInt8], in base: UnsafeRawPointer, count: Int) -> [Int] {
        var result: [Int] = []
        var offset = 0
        needle.withUnsafeBytes { pattern in
            while offset < count,
                  let hit = memmem(base + offset, count - offset, pattern.baseAddress, pattern.count) {
                let position = base.distance(to: UnsafeRawPointer(hit))
                result.append(position)
                offset = position + pattern.count
            }
        }
        return result
    }

    static func seed(in base: UnsafeRawPointer, from start: Int, to end: Int) -> Int? {
        guard end > start else { return nil }
        let hit = seedTag.withUnsafeBytes { pattern in
            memmem(base + start, end - start, pattern.baseAddress, pattern.count)
        }
        guard let hit else { return nil }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var index = base.distance(to: UnsafeRawPointer(hit)) + seedTag.count
        var value = 0
        var digits = 0
        while index < end, bytes[index] >= UInt8(ascii: "0"), bytes[index] <= UInt8(ascii: "9"), digits < 19 {
            value = value * 10 + Int(bytes[index] - UInt8(ascii: "0"))
            digits += 1
            index += 1
        }
        return digits > 0 ? value : nil
    }

    static func startOfLine(containing offset: Int, in base: UnsafeRawPointer) -> Int {
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var index = offset
        while index > 0, bytes[index - 1] != UInt8(ascii: "\n") { index -= 1 }
        return index
    }

    static func newlines(in base: UnsafeRawPointer, count: Int) -> Int {
        var lines = 0
        var offset = 0
        while offset < count, let hit = memchr(base + offset, Int32(UInt8(ascii: "\n")), count - offset) {
            lines += 1
            offset = base.distance(to: UnsafeRawPointer(hit)) + 1
        }
        return lines
    }
}
