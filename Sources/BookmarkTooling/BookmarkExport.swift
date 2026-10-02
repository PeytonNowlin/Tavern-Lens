import Foundation
import TavernEngine

/// Exports bookmarks as golden cases into a checkout of this repository: the repo-relative
/// paths and the file writing live here, outside `TavernEngine`, which keeps only the case's
/// format (`BookmarkGoldenCase`) and its redaction.
public enum BookmarkExport {
    /// Where committed cases live, relative to the repository root.
    public static let casesDirectory = "Tests/TavernEngineTests/Golden/Bookmarks"
    /// The private fixtures directory, relative to the repository root (git-ignored).
    public static let fixturesDirectory = "fixtures/private-logs"

    /// A file-name-safe default name, e.g. `bookmark-1172082863-t6-combat-3f2a9c`.
    public static func defaultName(for bookmark: FeedbackBookmark) -> String { bookmark.defaultCaseName }

    /// Writes `bookmark` as a golden case under `root`:
    /// - the lines it replays, copied out of `powerLog`, to
    ///   `fixtures/private-logs/bookmarks/<name>/Power.log` (private, git-ignored);
    /// - the redacted case to `Tests/TavernEngineTests/Golden/Bookmarks/<name>.json` (committed).
    ///
    /// The copy is replayed, with the engine set up as the live one was (`setup`), before
    /// anything is written, and the export fails unless it reaches the bookmarked state.
    @discardableResult
    public static func export(
        _ bookmark: FeedbackBookmark, powerLog: URL, name: String? = nil, into root: URL, setup: EngineSetup = EngineSetup()
    ) throws -> (goldenCase: BookmarkGoldenCase, caseFile: URL, logFile: URL) {
        let name = sanitized(name ?? defaultName(for: bookmark))
        guard FileManager.default.fileExists(atPath: powerLog.path(percentEncoded: false)) else {
            throw BookmarkReplayError.missingLog(powerLog.path(percentEncoded: false))
        }
        let cut = bookmark.cut.locating(in: powerLog)
        guard let start = cut.startByteOffset, let end = cut.endByteOffset, end >= start else {
            throw BookmarkReplayError.logTooShort(lines: 0, needed: cut.endLine)
        }
        let slice = try bytes(of: powerLog, from: start, to: end)
        var sliceCut = cut
        sliceCut.startByteOffset = 0
        sliceCut.endByteOffset = UInt64(slice.count)
        // The slice's line numbers are the original's (reading starts at the cut's first line).

        let logPath = "bookmarks/\(name)/Power.log"
        let goldenCase = BookmarkGoldenCase(
            name: name, note: bookmark.note, bookmarkID: bookmark.id, log: logPath, cut: sliceCut,
            resumed: bookmark.resumed, expected: bookmark.shown, expectedAdvice: bookmark.advice,
            adviceRequest: bookmark.adviceRequest, screenTribes: bookmark.screenTribes
        )
        let json = try goldenCase.encoded()
        guard !BookmarkGoldenCase.containsBattleTag(String(decoding: json, as: UTF8.self)) else {
            throw BookmarkReplayError.containsBattleTag
        }

        let logFile = root.appending(path: fixturesDirectory).appending(path: logPath)
        let caseFile = root.appending(path: casesDirectory).appending(path: "\(name).json")
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try slice.write(to: logFile, options: .atomic)
        guard try goldenCase.replay(powerLog: logFile, setup: setup) == goldenCase.expected else {
            try? fileManager.removeItem(at: logFile.deletingLastPathComponent())
            throw BookmarkReplayError.replayDiffers
        }
        try fileManager.createDirectory(at: caseFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json.write(to: caseFile, options: .atomic)
        return (goldenCase, caseFile, logFile)
    }

    static func sanitized(_ name: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-_")
        let mapped = String(name.lowercased().map { allowed.contains($0) ? $0 : "-" })
        return mapped.isEmpty ? "bookmark" : mapped
    }

    private static func bytes(of url: URL, from start: UInt64, to end: UInt64) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: start)
        return try handle.read(upToCount: Int(end - start)) ?? Data()
    }
}
