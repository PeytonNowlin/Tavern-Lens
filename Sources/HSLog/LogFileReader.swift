import Foundation

/// Reads a whole log file from disk as lines, in chunks, for replay.
///
/// Live tailing (`LogSessionFollower`) builds on the same `LogLineSplitter`.
public enum LogFileReader {
    public static let defaultChunkSize = 1 << 20

    /// Calls `line` for every line of the file, including an unterminated last line.
    /// With `offset`, reading starts at that byte (the start of a line).
    public static func forEachLine(
        in url: URL,
        from offset: UInt64 = 0,
        chunkSize: Int = defaultChunkSize,
        _ line: (String) throws -> Void
    ) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        if offset > 0 { try handle.seek(toOffset: offset) }
        var splitter = LogLineSplitter()
        var failure: Error?
        while failure == nil, let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            splitter.append(chunk) { text in
                guard failure == nil else { return }
                do { try line(text) } catch { failure = error }
            }
        }
        if let failure { throw failure }
        if let last = splitter.finish() { try line(last) }
    }
}
