import Foundation
import HSLog
import Testing
import TavernEngine

/// Seam 1 on the captured games: the advisor's request at every recruit publish (as `LivePipeline`
/// asks for it), its golden advice at the start of each late recruit phase, and feedback bookmarks
/// that capture the advice and replay to it. Skipped when the private fixtures are absent.
@Suite("Advisor in captured games")
struct AdvisorFixtureTests {
    static let games = [Fixtures.fullGame, Fixtures.truncatedGame, OddsPreviewFixtureTests.stressGame]

    @Test("A request at every recruit publish, listing exactly the cards the overlay shows, and none outside recruit",
          arguments: games)
    func requests(game: String) throws {
        guard Fixtures.isAvailable(game) else { return }  // the private fixture log isn't present
        let replay = try AdvisorFixture.replay(game)
        #expect(!replay.requests.isEmpty)
        #expect(replay.outsideRecruit == 0)
        #expect(replay.mismatches.isEmpty, "\(replay.mismatches.prefix(5))")
        // Level, roll and freeze prices come from the tavern buttons on screen, which the game
        // re-creates as a turn starts (so a publish or two can come before them).
        let buttons = { (r: AdvisorRequest) in r.rollCost != nil && r.canFreeze && (r.levelCost != nil || r.tier >= 6) }
        #expect(replay.requests.filter { !buttons($0) }.count <= 2)
        for (turn, request) in replay.mostGold { #expect(buttons(request), "turn \(turn)") }
        for request in replay.requests {
            if let input = request.preview.input {
                // The local side is the preview's, minion for minion.
                let minions = input.playerBoard.board.filter { entity in request.board.contains { $0.entity == entity } }
                #expect(minions.count == request.board.count)
            }
        }
    }

    @Test("The start of each late recruit phase of the full game scores to its golden advice",
          .enabled(if: Fixtures.isAvailable(Fixtures.fullGame), "private fixture log not present"))
    func goldenAdvice() async throws {
        let replay = try AdvisorFixture.replay(Fixtures.fullGame, builds: BuildFixture.catalog)
        let simulate = try AdvisorFixture.simulate()
        var advice: [String: AdviceView] = [:]
        for turn in 8...12 {
            let request = try #require(replay.mostGold[turn], "turn \(turn)")
            #expect(request.hasData, "the next opponent was seen by turn \(turn)")
            let done = try await AdvisorEvaluation.run(request, plan: AdvisorFixture.plan, simulate: simulate)
            #expect(done.isComplete)
            for suggestion in done.advice.suggestions {
                #expect(!suggestion.reason.isEmpty && !suggestion.targets.isEmpty, "turn \(turn): \(suggestion.action)")
            }
            #expect(AdvisorSanity.violations(done.advice, request: request).isEmpty, "turn \(turn)")
            // The lobby term: every living opponent seen but the next one, as they are now.
            let lobby = try #require(request.lobby, "turn \(turn)")
            #expect(!lobby.isEmpty && !lobby.contains { $0.playerID == request.preview.opponentPlayerID })
            #expect(lobby.allSatisfy { $0.seenTurn < turn && $0.side.player.hpLeft > 0 })
            #expect(request.builds?.isEmpty == false, "turn \(turn): a build detected (Aberration Discard from turn 7)")
            advice["turn-\(turn)"] = AdviceView(
                request: request, plan: AdvisorFixture.plan, advice: done.advice, evaluations: done.evaluations,
                isComplete: true
            )
        }
        try AdvisorFixture.verify(advice, golden: "full-game-advice")

        // The fixture-free golden state: turn 11 against the opponent's board as it actually was.
        var request = try #require(replay.mostGold[11])
        let combat = try CombatGoldens.input(CombatGoldens.fullGameTurn11)
        request.preview.input?.opponentBoard = combat.opponentBoard
        request.preview.opponentSeenTurn = 10
        try AdvisorFixture.verify(request, golden: "\(AdvisorSimulatorTests.turn11).request")
    }

    @Test("A bookmark keeps the advice shown, in its game's record, and replays to exactly that advice",
          .enabled(if: Fixtures.isAvailable(Fixtures.fullGame), "private fixture log not present"))
    func bookmark() async throws {
        let url = try #require(Fixtures.url(Fixtures.fullGame))
        let replay = try AdvisorFixture.replay(Fixtures.fullGame)
        let line = try #require(replay.mostGoldLine[11])

        var engine = TavernEngine()
        struct Reached: Error {}
        do {
            try LogFileReader.forEachLine(in: url) { text in
                engine.ingest(text)
                if engine.linesRead >= line { throw Reached() }
            }
        } catch is Reached {}
        let request = try #require(engine.advisorRequest)
        #expect(request == replay.mostGold[11])

        // The advice as the overlay showed it partway through scoring.
        let partway = try await AdvisorEvaluation.run(
            request, plan: AdvisorFixture.plan, limit: 12, simulate: try AdvisorFixture.simulate()
        )
        let shown = AdviceView(request: request, plan: AdvisorFixture.plan, advice: partway.advice, evaluations: partway.evaluations)
        var bookmark = try #require(engine.bookmark(note: "advisor at turn 11"))
        bookmark.cut = bookmark.cut.locating(in: url)
        bookmark.advice = shown
        bookmark.adviceRequest = request
        let added = engine.addBookmark(bookmark)
        #expect(added)

        // Saved with its game's record and read back.
        let record = try #require(engine.records.first { $0.gameSeed == bookmark.gameSeed })
        let directory = FileManager.default.temporaryDirectory.appending(path: "TavernLensAdvisor-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GameRecordStore(directory: directory)
        try store.save(record)
        let saved = store.allBookmarks().first { $0.bookmark.id == bookmark.id }?.bookmark
        #expect(saved?.advice == shown)
        #expect(saved?.adviceRequest == request, "kept for re-scoring without the log")
        #expect(saved.flatMap { AdvisorCase(bookmark: $0) }?.recorded == shown)

        let replayed = try await TavernEngine.replayAdvice(
            shown, cut: bookmark.cut, powerLog: url, simulate: try AdvisorFixture.simulate()
        )
        #expect(replayed == shown)

        // Advice for an earlier state than the bookmarked one is told apart.
        var stale = shown
        stale.fingerprint = "0"
        await #expect(throws: BookmarkReplayError.adviceForAnotherState) {
            _ = try await TavernEngine.replayAdvice(stale, cut: bookmark.cut, powerLog: url, simulate: try AdvisorFixture.simulate())
        }

        // As a golden case: the bookmarked state and its advice.
        let goldenCase = BookmarkGoldenCase(
            name: Self.committedCase, note: "Fixture: turn 11 recruit as the shop opened, with the advisor partway",
            log: Fixtures.fullGame, cut: bookmark.cut, expected: bookmark.shown, expectedAdvice: shown,
            adviceRequest: request
        )
        #expect(try goldenCase.replay(powerLog: url) == goldenCase.expected)
        let file = BookmarkGoldenTests.directory.appending(path: "\(Self.committedCase).json")
        if GoldenHarness.isRecording, !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
            try goldenCase.encoded().write(to: file)
        }
    }

    static let committedCase = "full-game-turn-11-recruit-advice"
}
