/// Splits a byte stream into log lines.
///
/// Hearthstone writes `\n`-terminated lines. Bytes after the last `\n` are held
/// back until more data arrives (a live tail can cut a line in half), and every
/// line is decoded as UTF-8 with replacement so a corrupt byte never stops parsing.
/// A trailing `\r` is dropped.
public struct LogLineSplitter: Sendable {
    private var pending: [UInt8] = []

    public init() {}

    /// Feeds a chunk of bytes and calls `line` for each complete line in it.
    public mutating func append<Bytes: Collection<UInt8>>(_ bytes: Bytes, line: (String) -> Void) {
        var lineStart = bytes.startIndex
        var index = bytes.startIndex
        while index != bytes.endIndex {
            if bytes[index] == 0x0A {
                if pending.isEmpty {
                    line(Self.decode(bytes[lineStart..<index]))
                } else {
                    pending.append(contentsOf: bytes[lineStart..<index])
                    line(Self.decode(pending))
                    pending.removeAll(keepingCapacity: true)
                }
                lineStart = bytes.index(after: index)
            }
            index = bytes.index(after: index)
        }
        pending.append(contentsOf: bytes[lineStart..<bytes.endIndex])
    }

    /// Returns the unterminated last line, if any, and clears it.
    /// Call this at end of file when replaying; a live tail keeps waiting instead.
    public mutating func finish() -> String? {
        guard !pending.isEmpty else { return nil }
        defer { pending.removeAll() }
        return Self.decode(pending)
    }

    private static func decode<Bytes: Collection<UInt8>>(_ bytes: Bytes) -> String {
        var slice = Array(bytes)
        if slice.last == 0x0D { slice.removeLast() }
        return String(decoding: slice, as: UTF8.self)
    }
}
