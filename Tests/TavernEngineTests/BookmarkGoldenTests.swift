import Foundation
import HSLog
import Testing
import TavernEngine

/// Seam 1 golden cases made from feedback bookmarks: every `Golden/Bookmarks/<name>.json`
/// replays its log stretch to the state the player bookmarked.
///
/// Add a case with the debug window's "Export Golden Case…" (choose this repository's
/// root): it writes the case JSON here and the log stretch it needs to
/// `fixtures/private-logs/bookmarks/<name>/Power.log`, which is git-ignored. A case whose
/// log isn't present is skipped. `TAVERN_RECORD_GOLDENS=1` re-records `expected` after an
/// intended engine change; review the diff.
@Suite("Bookmark golden cases")
struct BookmarkGoldenTests {
    static let directory = GoldenHarness.goldenDirectory.appending(path: "Bookmarks", directoryHint: .isDirectory)

    static var caseFiles: [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        return files.filter { $0.hasSuffix(".json") }.sorted()
    }

    static var anyCaseRunnable: Bool {
        caseFiles.contains { file in
            (try? Data(contentsOf: directory.appending(path: file)))
                .flatMap { try? BookmarkGoldenCase.decode($0) }
                .map { Fixtures.isAvailable($0.log) } ?? false
        }
    }

    @Test("Committed cases are redacted and well formed", arguments: caseFiles)
    func wellFormed(file: String) throws {
        let data = try Data(contentsOf: Self.directory.appending(path: file))
        #expect(!BookmarkGoldenCase.containsBattleTag(String(decoding: data, as: UTF8.self)))
        let goldenCase = try BookmarkGoldenCase.decode(data)
        #expect("\(goldenCase.name).json" == file)
        #expect(goldenCase.format == BookmarkGoldenCase.currentFormat)
        #expect(goldenCase.expected == goldenCase.expected.redactingNames())
        #expect(goldenCase.expected.position.line == goldenCase.cut.endLine)
    }

    @Test("Each case replays to its bookmarked state", .enabled(if: anyCaseRunnable, "no case's log is present"),
          arguments: caseFiles)
    func replays(file: String) throws {
        let url = Self.directory.appending(path: file)
        var goldenCase = try BookmarkGoldenCase.decode(Data(contentsOf: url))
        // Logs are private; a case whose log isn't on this machine has nothing to check.
        guard let log = Fixtures.url(goldenCase.log) else { return }
        let replayed = try #require(try goldenCase.replay(powerLog: log))
        if GoldenHarness.isRecording {
            goldenCase.expected = replayed
            try goldenCase.encoded().write(to: url)
            return
        }
        #expect(replayed == goldenCase.expected, "\(goldenCase.name): \(goldenCase.note)")
    }

    @Test("Each case with advice re-scores to the advice shown", .enabled(if: anyCaseRunnable, "no case's log is present"),
          arguments: caseFiles)
    func adviceReplays(file: String) async throws {
        let url = Self.directory.appending(path: file)
        var goldenCase = try BookmarkGoldenCase.decode(Data(contentsOf: url))
        guard let expected = goldenCase.expectedAdvice, let log = Fixtures.url(goldenCase.log) else { return }
        let simulator = try CombatGoldens.makeSimulator()
        let replayed = try await goldenCase.replayAdvice(powerLog: log, simulate: AdvisorEvaluation.simulate(on: { simulator }))
        if GoldenHarness.isRecording {
            goldenCase.expectedAdvice = replayed
            try goldenCase.encoded().write(to: url)
            return
        }
        #expect(replayed == expected, "\(goldenCase.name): \(goldenCase.note)")
    }
}

/// Bookmarks on the captured full game, attached mid-game like the live app.
@Suite("Feedback bookmarks on a captured game")
struct BookmarkFixtureTests {
    static let committedCase = "full-game-turn-6-combat"

    @Test(
        "Bookmarks taken while following the full game replay to the identical snapshot",
        .enabled(if: Fixtures.isAvailable(Fixtures.fullGame), "private fixture log not present")
    )
    func fullGame() throws {
        let url = try #require(Fixtures.url(Fixtures.fullGame))
        let session = try #require(LogSession(directory: url.deletingLastPathComponent(), timeZone: .gmt))
        // Attach at turn 4 (about 30% in), then follow to the end.
        let reference = try FixtureReplays.result(Fixtures.fullGame)
        let attach = try #require(reference.timeline.first { $0.state.game?.bgTurn == 4 }).position.line
        var live = try LiveRead(url: url, session: session, caughtUpAt: attach)

        // Right after attaching, the start of turn 6 combat, and game over.
        var marks: [(String, FeedbackBookmark)] = [("attached", try live.bookmark())]
        let targets: [(String, (TimelineEntry) -> Bool)] = [
            (Self.committedCase, { $0.state.game?.bgTurn == 6 && $0.state.game?.phase == .combat }),
            ("game over", { $0.state.status == .gameOver }),
        ]
        for (name, matches) in targets {
            let line = try #require(reference.timeline.first(where: matches)).position.line
            live.follow(through: line + 25)
            marks.append((name, try live.bookmark(note: name)))
        }

        for (name, bookmark) in marks {
            #expect(bookmark.cut.startLine == 2 && bookmark.cut.startByteOffset != nil && bookmark.cut.endByteOffset != nil)
            let replayed = try TavernEngine.replay(bookmark, powerLog: url)
            #expect(replayed.timeline.only == bookmark.shown, "\(name) at line \(bookmark.cut.endLine)")
        }
        #expect(marks.last?.1.shown.state.status == .gameOver)

        // The combat bookmark as a golden case referring to the fixture log itself.
        let combat = try #require(marks.first { $0.0 == Self.committedCase }?.1)
        let goldenCase = BookmarkGoldenCase(
            name: Self.committedCase, note: "Fixture: start of turn 6 combat, attached mid-game at turn 4",
            log: Fixtures.fullGame, cut: combat.cut, expected: combat.shown
        )
        #expect(try goldenCase.replay(powerLog: url) == goldenCase.expected)
        let file = BookmarkGoldenTests.directory.appending(path: "\(Self.committedCase).json")
        if GoldenHarness.isRecording, !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: BookmarkGoldenTests.directory, withIntermediateDirectories: true)
            try goldenCase.encoded().write(to: file)
        }

        // Exported, the case replays from its own copy of the log stretch.
        let root = FileManager.default.temporaryDirectory.appending(path: "TavernLensExport-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let exported = try BookmarkExport.export(combat, powerLog: url, into: root)
        let size = try #require(try exported.logFile.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        #expect(UInt64(size) == combat.cut.endByteOffset! - combat.cut.startByteOffset!)
        #expect(try exported.goldenCase.replay(powerLog: exported.logFile) == exported.goldenCase.expected)
    }
}
