import Darwin
import Foundation

/// Byte offsets of lines in a log file, found by counting newlines in the raw bytes
/// (memory-mapped), so locating a line in a large log takes milliseconds.
public enum LogLineOffsets {
    /// The byte offset just past line `line` (after its `\n`), counting from a known line
    /// start: `startLine` begins at `startOffset`. Returns the file's length when the line
    /// is its unterminated last one, and nil when the file is shorter or can't be read.
    public static func end(ofLine line: Int, in url: URL, startLine: Int = 1, startOffset: UInt64 = 0) -> UInt64? {
        guard line >= startLine, let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        return end(ofLine: line, in: data, startLine: startLine, startOffset: startOffset)
    }

    /// `end(ofLine:in:startLine:startOffset:)` on a log's bytes.
    public static func end(ofLine line: Int, in data: Data, startLine: Int = 1, startOffset: UInt64 = 0) -> UInt64? {
        guard line >= startLine, startOffset <= UInt64(data.count) else { return nil }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> UInt64? in
            guard let base = raw.baseAddress else { return nil }
            var offset = Int(startOffset)
            var remaining = line - startLine + 1
            while remaining > 0 {
                guard offset < raw.count else { return nil }
                guard let hit = memchr(base + offset, Int32(UInt8(ascii: "\n")), raw.count - offset) else {
                    // An unterminated last line.
                    return remaining == 1 ? UInt64(raw.count) : nil
                }
                offset = base.distance(to: UnsafeRawPointer(hit)) + 1
                remaining -= 1
            }
            return UInt64(offset)
        }
    }
}
