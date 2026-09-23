import Foundation
import HSLog
import Testing

/// Byte offsets of lines, for bookmarks that point into a Power.log, and reading from one.
@Suite("Line byte offsets")
struct LogLineOffsetsTests {
    static let text = "first\nsecond\r\nthird é\n\nfifth"
    static var data: Data { Data(text.utf8) }

    @Test("The end of each line is just past its newline; the last, unterminated line ends at EOF")
    func ends() {
        let d = Self.data
        #expect(LogLineOffsets.end(ofLine: 1, in: d) == 6)
        #expect(LogLineOffsets.end(ofLine: 2, in: d) == 14)
        #expect(LogLineOffsets.end(ofLine: 3, in: d) == 23)  // "third é" is 8 bytes
        #expect(LogLineOffsets.end(ofLine: 4, in: d) == 24)
        #expect(LogLineOffsets.end(ofLine: 5, in: d) == UInt64(d.count))
        #expect(LogLineOffsets.end(ofLine: 6, in: d) == nil)
        #expect(LogLineOffsets.end(ofLine: 0, in: d) == nil)
    }

    @Test("Counting from a known line start gives the same offsets")
    func fromKnownStart() {
        let d = Self.data
        #expect(LogLineOffsets.end(ofLine: 3, in: d, startLine: 2, startOffset: 6) == 23)
        #expect(LogLineOffsets.end(ofLine: 2, in: d, startLine: 2, startOffset: 6) == 14)
        #expect(LogLineOffsets.end(ofLine: 1, in: d, startLine: 2, startOffset: 6) == nil)
    }

    @Test("Reading from a byte offset starts at that line")
    func readFromOffset() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "TavernLensOffsets-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "Power.log")
        try Self.data.write(to: url)

        var lines: [String] = []
        try LogFileReader.forEachLine(in: url, from: 6, chunkSize: 4) { lines.append($0) }
        #expect(lines == ["second", "third é", "", "fifth"])
        #expect(LogLineOffsets.end(ofLine: 2, in: url) == 14)
    }
}
