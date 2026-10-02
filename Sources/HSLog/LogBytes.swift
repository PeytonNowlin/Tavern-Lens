import Darwin
import Foundation

/// Raw-byte helpers shared by the Power.log scanners (`PowerLogEntryPoint`,
/// `PowerLogGames`, `LogLineOffsets`).
enum LogBytes {
    /// The file's bytes, read through a file handle and capped at the size seen when the
    /// read starts. Power.log is live: the game truncates or rewrites it on a new launch,
    /// and a memory-mapped read of a file that shrinks underneath it dies with SIGBUS.
    /// A read that races a shrink just returns fewer bytes. Nil when the file can't be read.
    static func read(_ url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = (try? handle.seekToEnd()).map(Int.init), (try? handle.seek(toOffset: 0)) != nil else { return nil }
        var data = Data()
        data.reserveCapacity(size)
        while data.count < size {
            guard let chunk = try? handle.read(upToCount: min(size - data.count, 8 << 20)), !chunk.isEmpty else { break }
            data.append(chunk)
        }
        return data
    }

    /// Number of `\n` bytes in `base[start..<end]`.
    static func newlines(in base: UnsafeRawPointer, from start: Int = 0, to end: Int) -> Int {
        var lines = 0
        var offset = start
        while offset < end, let hit = memchr(base + offset, Int32(UInt8(ascii: "\n")), end - offset) {
            lines += 1
            offset = base.distance(to: UnsafeRawPointer(hit)) + 1
        }
        return lines
    }
}
