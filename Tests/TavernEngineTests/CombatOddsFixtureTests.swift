import Foundation
import HSData
import Testing
import TavernEngine

/// Seam 1 on the captured games: the engine's combat-start simulator input, and the odds the
/// pinned simulator gives for it, against docs/research/simulator-input-mapping.md §8.
/// Skipped when the private fixtures are absent (`CombatOddsGoldenTests` still runs on the
/// committed inputs).
@Suite("Combat odds in captured games")
struct CombatOddsFixtureTests {
    @Test(
        "Full game: one request per combat, at the 2022 edge, against the combat opponent; turn 11 is the §8.1 input",
        .enabled(if: Fixtures.isAvailable(Fixtures.fullGame), "private fixture log not present")
    )
    func fullGame() throws {
        let result = try TavernEngine.replay(fileAt: #require(Fixtures.url(Fixtures.fullGame)))
        let requests = result.combatRequests
        #expect(requests.map(\.bgTurn) == Array(1...12))
        let seen = try #require(result.records.first?.journal.boardsSeen)
        #expect(requests.map(\.opponentPlayerID) == seen.sorted { $0.bgTurn < $1.bgTurn }.map(\.playerID))
        #expect(requests.map(\.position) == seen.sorted { $0.bgTurn < $1.bgTurn }.map(\.position))
        #expect(Set(requests.map(\.id)).count == 12)

        let turn11 = try #require(requests.first { $0.bgTurn == 11 })
        #expect(turn11.position.line == 223_038)
        let input = turn11.input
        let local = input.playerBoard.player
        let opponent = input.opponentBoard.player
        #expect(local.cardId == "TB_BaconShop_HERO_15" && local.hpLeft == 16 && local.tavernTier == 6)
        #expect(opponent.cardId == "BG36_HERO_000" && opponent.hpLeft == 27 && opponent.tavernTier == 4)
        #expect(input.playerBoard.board.count == 7 && input.opponentBoard.board.count == 7)
        #expect(opponent.hand.map(\.cardId) == ["BG36_102", "BG36_102", "BG36_106", "BG36_115", "BG36_311"])
        #expect(local.secrets.first { $0.cardId == "BG_OldGod" }?.tags == ["4914": 236, "4915": 222])
        #expect(opponent.secrets.first { $0.cardId == "BG_OldGod" }?.tags == ["4914": 230, "4915": 338])
        #expect(opponent.trinkets.map(\.cardId) == ["BG36_MagicItem_404", "BG36_MagicItem_403t"])
        #expect(opponent.trinkets.map(\.scriptDataNum1) == [4, 34])
        #expect(local.globalInfo["TavernSpellsCastThisGame"] == 20 && local.globalInfo["GoldSpentThisGame"] == 86)
        #expect(opponent.globalInfo["TavernSpellsCastThisGame"] == 32 && opponent.globalInfo["CardsDiscardedThisGame"] == 16)
        #expect(opponent.globalInfo["BattlecriesTriggeredThisGame"] == 5)
        #expect(input.gameState.currentTurn == 11 && input.gameState.numberOfPlayersAlive == 6)
        #expect(input.gameState.anomalies.isEmpty && input.gameState.anomalyDbfIds == nil)
        // No card data in this replay, so the stand-in tribe source knows nothing: every tribe.
        #expect(input.gameState.validTribes == nil && !turn11.tribesKnown)
        #expect(input.options.applyDamageCap)
        try CombatGoldens.verify(input, golden: CombatGoldens.fullGameTurn11)

        // Equal to the committed input, which `CombatOddsGoldenTests` simulates: about a 74% loss,
        // with a range covering the real 10 damage.
    }

    @Test(
        "Full game with the pool: once the tribes resolve, every combat's input carries the inferred lobby",
        .enabled(if: Fixtures.isAvailable(Fixtures.fullGame), "private fixture log not present")
    )
    func fullGameResolvedTribes() throws {
        let result = try TavernEngine.replay(fileAt: #require(Fixtures.url(Fixtures.fullGame)), pool: PoolFixture.pool)
        let lobby: [HS.Race] = [.aberration, .dragon, .elemental, .quilboar, .undead]
        let requests = result.combatRequests
        #expect(requests.map(\.bgTurn) == Array(1...12))
        // The tribes resolve by BG turn 4 (`TribeFixtureTests`); from then on the simulator gets them.
        for request in requests where request.bgTurn >= 4 {
            #expect(request.input.gameState.validTribes == lobby.map(\.rawValue).sorted(), "turn \(request.bgTurn)")
            #expect(request.tribesKnown)
        }
        // Apart from the tribes, the turn-11 input is the golden one.
        var turn11 = try #require(requests.first { $0.bgTurn == 11 }).input
        turn11.gameState.validTribes = nil
        try CombatGoldens.verify(turn11, golden: CombatGoldens.fullGameTurn11)
    }

    @Test(
        "Truncated game: the turn-4 combat drops the placeholder trinkets and matches §8.2",
        .enabled(if: Fixtures.isAvailable(Fixtures.truncatedGame), "private fixture log not present")
    )
    func truncatedGame() throws {
        let result = try TavernEngine.replay(fileAt: #require(Fixtures.url(Fixtures.truncatedGame)))
        let turn4 = try #require(result.combatRequests.first { $0.bgTurn == 4 })
        #expect(turn4.position.line == 36_936)
        let input = turn4.input
        #expect(input.playerBoard.player.cardId == "BG36_HERO_002")
        #expect(input.playerBoard.player.hpLeft == 34)
        #expect(input.playerBoard.player.trinkets.isEmpty)
        #expect(input.playerBoard.player.heroPowers.first?.info3 == 2)
        #expect(input.opponentBoard.player.cardId == "BG31_HERO_003" && input.opponentBoard.player.hpLeft == 39)
        #expect(input.playerBoard.board.count == 5 && input.opponentBoard.board.count == 3)
        #expect(input.opponentBoard.player.secrets.first { $0.cardId == "BG_OldGod" }?.tags == ["4914": 5, "4915": 5])
        try CombatGoldens.verify(input, golden: CombatGoldens.truncatedGameTurn4)
        // `CombatOddsGoldenTests` simulates it: about a 96% loss for 3–4.
    }
}
