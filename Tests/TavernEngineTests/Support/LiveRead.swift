import Foundation
import HSLog
import Testing
import TavernEngine

/// Reads a Power.log the way `LivePipeline` does: an engine set up as the pipeline sets up
/// each one (`TavernEngine(setup:)`), carry in a record, start at the entry point, catch up
/// silently on the lines already written, then follow line by line, taking in screen
/// readings as they come.
struct LiveRead {
    var engine: TavernEngine
    let lines: [String]
    let url: URL
    let setup: EngineSetup

    /// - Parameters:
    ///   - caughtUpAt: the file's line count when the app attached (the catch-up ends after it).
    ///   - setup: the live data (pool, builds, hero stats) the pipeline's engines get.
    init(
        url: URL, session: LogSession? = nil, resuming record: GameRecord? = nil, caughtUpAt: Int,
        setup: EngineSetup = EngineSetup()
    ) throws {
        var lines: [String] = []
        try LogFileReader.forEachLine(in: url) { lines.append($0) }
        self.lines = lines
        self.url = url
        self.setup = setup
        engine = TavernEngine(setup: setup, session: session, timeZone: .gmt)
        if let record { engine.resume(record) }
        let entry = try #require(PowerLogEntryPoint.find(in: url))
        engine.start(at: entry)
        engine.beginCatchUp()
        for line in lines[(entry.line - 1)..<caughtUpAt] { engine.ingest(line) }
        engine.endCatchUp()
    }

    /// Follows the log up to and including line `line`.
    mutating func follow(through line: Int) {
        while engine.linesRead < min(line, lines.count) {
            engine.ingest(lines[engine.linesRead])
        }
    }

    /// A hero-pick banner reading arrives (the pipeline's `ingestScreenTribes`).
    mutating func read(_ reading: ScreenTribeReading) {
        engine.ingestScreenTribes(reading)
    }

    /// Replays `bookmark` the way the debug window and export do: with the live setup.
    func replay(_ bookmark: FeedbackBookmark) throws -> TavernEngine {
        try TavernEngine.replay(bookmark, powerLog: url, setup: setup)
    }

    /// Takes the bookmark the pipeline would: the engine's moment plus the log's byte offsets.
    func bookmark(note: String = "") throws -> FeedbackBookmark {
        var bookmark = try #require(engine.bookmark(note: note))
        bookmark.powerLog = url.path(percentEncoded: false)
        bookmark.cut = bookmark.cut.locating(in: url)
        return bookmark
    }
}

extension SyntheticLog {
    /// Writes the lines as a Power.log (`\n`-terminated) in a temporary session folder.
    func write(session name: String = "Hearthstone_2026_09_22_21_08_40") throws -> (url: URL, session: LogSession) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TavernLensBookmarks-\(UUID().uuidString)/\(name)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "Power.log")
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        return (url, try #require(LogSession(directory: directory, timeZone: .gmt)))
    }
}
