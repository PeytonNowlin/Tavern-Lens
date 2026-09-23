import Foundation
import Testing
import TavernEngine

/// Seam 1 on the captured games. Skipped when the private fixtures are absent.
@Suite("Replay of captured games")
struct FixtureReplayTests {
    @Test(
        "Full game: one solo BG game, start to end, George the Fallen, final BG turn 12",
        .enabled(if: Fixtures.isAvailable(Fixtures.fullGame), "private fixture log not present")
    )
    func fullGame() throws {
        let result = try TavernEngine.replay(fileAt: #require(Fixtures.url(Fixtures.fullGame)))

        let game = try #require(result.games.only)
        #expect(game.gameType == "GT_BATTLEGROUNDS")
        #expect(game.start.line == 402)  // PowerTaskList CREATE_GAME
        #expect(game.end?.line == 269_962)  // PowerTaskList GameEntity STATE=COMPLETE
        #expect(game.localPlayerID == 6)
        #expect(game.localHeroCardID == "TB_BaconShop_HERO_15")
        #expect(game.bgTurn == 12)
        #expect(result.timeline.last?.state.status == .gameOver)
        expectCleanParse(result)

        try GoldenHarness.verify(
            result, golden: "full-game",
            checkpoints: [.first, .firstOfTurn(1), .firstOfTurn(6), .firstOfTurn(12), .firstWithStatus(.gameOver), .last]
        )
    }

    @Test(
        "Truncated game: one game with no end, no crash",
        .enabled(if: Fixtures.isAvailable(Fixtures.truncatedGame), "private fixture log not present")
    )
    func truncatedGame() throws {
        let result = try TavernEngine.replay(fileAt: #require(Fixtures.url(Fixtures.truncatedGame)))

        let game = try #require(result.games.only)
        #expect(game.end == nil)
        #expect(game.localPlayerID == 2)
        #expect(game.bgTurn == 5)
        #expect(result.timeline.last?.state.status == .inGame)
        expectCleanParse(result)

        try GoldenHarness.verify(
            result, golden: "truncated-game",
            checkpoints: [.first, .firstOfTurn(1), .firstOfTurn(5), .last]
        )
    }

    /// The validated parsing rules leave nothing unexplained in the captured logs.
    private func expectCleanParse(_ result: ReplayResult, sourceLocation: SourceLocation = #_sourceLocation) {
        let d = result.diagnostics
        #expect(d.parse.unparsableLines == 0, sourceLocation: sourceLocation)
        #expect(d.parse.orphanTagLines == 0, sourceLocation: sourceLocation)
        #expect(d.parse.malformedPowerLines == 0, sourceLocation: sourceLocation)
        #expect(d.parse.unreadableEntityRefs == 0, sourceLocation: sourceLocation)
        #expect(d.store.unboundPlayerNames == 0, sourceLocation: sourceLocation)
        #expect(d.store.implicitEntities == 0, sourceLocation: sourceLocation)
    }
}

extension Collection {
    /// The single element, or nil when there are zero or several.
    var only: Element? { count == 1 ? first : nil }
}
