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
/// The search works on the raw bytes (read through a file handle, never memory-mapped: the
/// live file can shrink), so finding the entry in a large
/// log is cheap; the lines before it are never parsed.
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
        guard let data = LogBytes.read(url) else { return nil }
        return find(in: data)
    }

    /// The entry point of a log's bytes; nil when it has no game. It is the start of the
    /// latest game's slice (`PowerLogGames`), which already folds in same-seed reconnects.
    public static func find(in data: Data) -> PowerLogEntryPoint? {
        guard let slice = PowerLogGames.slices(in: data).last else { return nil }
        return PowerLogEntryPoint(byteOffset: UInt64(slice.byteRange.lowerBound), line: slice.line, gameSeed: slice.gameSeed)
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
}
