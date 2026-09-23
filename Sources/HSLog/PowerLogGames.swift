import Darwin
import Foundation

/// One game's own slice of a Power.log: from its `GameState` `CREATE_GAME` line up to
/// the next game's (or the end of the file). A reconnect inside the same file resends
/// `CREATE_GAME` with the same `GAME_SEED`; those blocks stay in one slice, so the
/// slice replays the whole game.
///
/// The slice is found on the raw bytes, like `PowerLogEntryPoint`; nothing is parsed.
public struct PowerLogGameSlice: Hashable, Sendable {
    /// Byte range of the slice in the file. It starts at the beginning of a line and
    /// ends after a newline (or at the end of the file).
    public var byteRange: Range<Int>
    /// The 1-based line number of the slice's first line in the file.
    public var line: Int
    /// `GAME_SEED` of the game, when its `CREATE_GAME` block had one.
    public var gameSeed: Int?

    public init(byteRange: Range<Int>, line: Int, gameSeed: Int?) {
        self.byteRange = byteRange
        self.line = line
        self.gameSeed = gameSeed
    }
}

public enum PowerLogGames {
    /// Every game in the file at `url`, in order; empty when it has none or can't be read.
    public static func slices(in url: URL) -> [PowerLogGameSlice] {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return [] }
        return slices(in: data)
    }

    /// Every game in a log's bytes, in order.
    public static func slices(in data: Data) -> [PowerLogGameSlice] {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [PowerLogGameSlice] in
            guard let base = raw.baseAddress, !raw.isEmpty else { return [] }
            let starts = PowerLogEntryPoint.occurrences(of: PowerLogEntryPoint.createGame, in: base, count: raw.count)
            var blocks: [(start: Int, seed: Int?)] = []
            for (index, hit) in starts.enumerated() {
                let end = index + 1 < starts.count ? starts[index + 1] : raw.count
                let seed = PowerLogEntryPoint.seed(
                    in: base, from: hit, to: min(end, hit + PowerLogEntryPoint.seedSearchLimit)
                )
                let lineStart = PowerLogEntryPoint.startOfLine(containing: hit, in: base)
                // A reconnect: same seed as the block before it, so the same game.
                if let seed, let last = blocks.last, last.seed == seed { continue }
                blocks.append((lineStart, seed))
            }
            var result: [PowerLogGameSlice] = []
            var line = 1
            var counted = 0
            for (index, block) in blocks.enumerated() {
                line += newlines(in: base, from: counted, to: block.start)
                counted = block.start
                let end = index + 1 < blocks.count ? blocks[index + 1].start : raw.count
                result.append(PowerLogGameSlice(byteRange: block.start..<end, line: line, gameSeed: block.seed))
            }
            return result
        }
    }

    private static func newlines(in base: UnsafeRawPointer, from start: Int, to end: Int) -> Int {
        var lines = 0
        var offset = start
        while offset < end, let hit = memchr(base + offset, Int32(UInt8(ascii: "\n")), end - offset) {
            lines += 1
            offset = base.distance(to: UnsafeRawPointer(hit)) + 1
        }
        return lines
    }
}
