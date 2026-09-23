import Foundation
import HSData
import HSLog
import Testing
import TavernEngine

/// Seam 1 on the captured games: the recruit-phase odds preview (the local board now against the
/// next opponent's last-seen board), asked for whenever the published state changes, as
/// `LivePipeline` does. Skipped when the private fixtures are absent.
@Suite("Odds preview in captured games")
struct OddsPreviewFixtureTests {
    static let stressGame = "Hearthstone_2026_09_22_22_34_47/Power.log"
    static let games = [Fixtures.fullGame, Fixtures.truncatedGame, stressGame]

    /// For one combat: the preview as it was at the recruit phase's last publish, and the combat's request.
    struct Pair: Sendable {
        var preview: OddsPreviewRequest
        var combat: CombatSimulationRequest
    }

    struct Replay: Sendable {
        var pairs: [Pair]
        /// Every distinct preview, in order.
        var previews: [OddsPreviewRequest]
        var combats: [CombatSimulationRequest]
        var records: [GameRecord]
        /// Publishes outside recruit that had a preview (should be none).
        var previewsOutsideRecruit = 0
    }

    private static let replays = Memo<String, Replay>()

    /// Read once per run for every test that looks at it.
    static func replay(_ path: String) throws -> Replay {
        try replays.value(path) { try computeReplay(path) }
    }

    private static func computeReplay(_ path: String) throws -> Replay {
        var engine = TavernEngine()
        var published = 0
        var latest: OddsPreviewRequest?
        var replay = Replay(pairs: [], previews: [], combats: [], records: [])
        try LogFileReader.forEachLine(in: #require(Fixtures.url(path))) { line in
            engine.ingest(line)
            if engine.combatRequests.count > replay.combats.count {
                replay.combats = engine.combatRequests
                if let latest, let combat = engine.combatRequests.last {
                    replay.pairs.append(Pair(preview: latest, combat: combat))
                }
                latest = nil
            }
            guard engine.timeline.count > published else { return }
            published = engine.timeline.count
            if engine.state.game?.phase == .recruit {
                latest = engine.oddsPreview
                if let latest, replay.previews.last != latest { replay.previews.append(latest) }
            } else if engine.oddsPreview != nil {
                replay.previewsOutsideRecruit += 1
            }
        }
        engine.finish()
        replay.records = engine.records
        return replay
    }

    @Test(
        "At the end of every recruit phase the preview is the coming combat with the opponent's last-seen side",
        arguments: games
    )
    func endOfRecruit(game: String) throws {
        guard Fixtures.isAvailable(game) else { return }  // the private fixture log isn't present
        let replay = try Self.replay(game)
        #expect(replay.previewsOutsideRecruit == 0)
        #expect(!replay.combats.isEmpty)
        #expect(replay.pairs.count == replay.combats.count, "a preview before every combat")

        var fought = 0, unseen = 0
        for pair in replay.pairs {
            let preview = pair.preview, combat = pair.combat
            let turn = "turn \(combat.bgTurn)"
            #expect(preview.bgTurn == combat.bgTurn && preview.gameSeed == combat.gameSeed, "\(turn)")
            #expect(preview.opponentPlayerID == combat.opponentPlayerID, "\(turn): previewed the combat's opponent")
            let earlier = replay.combats.last {
                $0.opponentPlayerID == combat.opponentPlayerID && $0.bgTurn < combat.bgTurn
            }
            guard let earlier else {
                // Never fought: no data, and nothing to simulate.
                #expect(!preview.hasData && preview.opponentSeenTurn == nil && preview.input == nil, "\(turn)")
                unseen += 1
                continue
            }
            fought += 1
            let input = try #require(preview.input, "\(turn): a fought opponent has data")
            #expect(preview.opponentSeenTurn == earlier.bgTurn && preview.opponentSource == .combatStart, "\(turn)")

            // The local side, the options and the game state are exactly what the combat got.
            #expect(input.playerBoard == combat.input.playerBoard, "\(turn): local side")
            #expect(input.options == combat.input.options && input.gameState == combat.input.gameState, "\(turn)")

            // The opponent is their side of the earlier combat, with health and tier as of now.
            var side = earlier.input.opponentBoard
            side.player.hpLeft = combat.input.opponentBoard.player.hpLeft
            side.player.tavernTier = combat.input.opponentBoard.player.tavernTier
            #expect(input.opponentBoard == side, "\(turn): the last-seen side, health and tier updated")

            // Had their board not changed, the preview would be the combat's input exactly.
            var unchanged = input
            unchanged.opponentBoard = combat.input.opponentBoard
            #expect(unchanged == combat.input, "\(turn)")
        }
        #expect(unseen > 0)
        if game != Fixtures.truncatedGame { #expect(fought > 0) }
    }

    @Test(
        "The preview follows the board through the recruit phase: buys, sells and repositions change it",
        .enabled(if: Fixtures.isAvailable(Fixtures.fullGame), "private fixture log not present")
    )
    func followsTheBoard() throws {
        let replay = try Self.replay(Fixtures.fullGame)
        let withData = replay.previews.filter(\.hasData)
        var turnsThatChanged = 0
        for turn in Set(withData.map(\.bgTurn)) {
            let boards = withData.filter { $0.bgTurn == turn }.compactMap { $0.input?.playerBoard.board.map(\.cardId) }
            if Set(boards).count > 1 { turnsThatChanged += 1 }
        }
        // Turns 8–12 have data, and the board changes within each.
        #expect(Set(withData.map(\.bgTurn)) == Set(8...12))
        #expect(turnsThatChanged == 5)
        // Every preview within a turn keeps the one opponent and their one last-seen side.
        for turn in 8...12 {
            let sides = Set(withData.filter { $0.bgTurn == turn }.compactMap { $0.input?.opponentBoard.board })
            #expect(sides.count == 1, "turn \(turn)")
        }
    }

    @Test(
        "Rebuilt from the history's last-seen board, the opponent's side has the seen minions and the saved mechanics",
        .enabled(if: Fixtures.isAvailable(Fixtures.fullGame), "private fixture log not present")
    )
    func rebuiltFromHistory() throws {
        let replay = try Self.replay(Fixtures.fullGame)
        let seen = try #require(replay.records.first?.journal.boardsSeen)
        #expect(seen.count == replay.combats.count)
        for (board, combat) in zip(seen.sorted { $0.bgTurn < $1.bgTurn }, replay.combats) {
            let exact = combat.input.opponentBoard
            let rebuilt = try #require(BattleInputBuilder.side(
                seen: board, heroCardID: exact.player.cardId, heroEntityID: exact.player.entityId,
                hpLeft: exact.player.hpLeft, tier: exact.player.tavernTier
            ))
            let turn = "turn \(combat.bgTurn)"
            #expect(rebuilt.board.map(\.cardId) == exact.board.map(\.cardId), "\(turn)")
            #expect(rebuilt.board.map(\.attack) == exact.board.map(\.attack), "\(turn)")
            #expect(rebuilt.board.map(\.health) == exact.board.map(\.health), "\(turn)")
            #expect(rebuilt.board.map(\.taunt) == exact.board.map(\.taunt), "\(turn)")
            #expect(rebuilt.board.map(\.divineShield) == exact.board.map(\.divineShield), "\(turn)")
            #expect(rebuilt.board.map(\.reborn) == exact.board.map(\.reborn), "\(turn)")
            #expect(rebuilt.player.cardId == exact.player.cardId, "\(turn)")
            #expect(rebuilt.player.secrets == exact.player.secrets, "\(turn): the Deity")
            #expect(rebuilt.player.trinkets == exact.player.trinkets, "\(turn)")
            #expect(rebuilt.player.heroPowers.map(\.cardId) == exact.player.heroPowers.map(\.cardId), "\(turn)")
            var counters = exact.player.globalInfo
            counters["ChoralAttackBuff"] = nil
            counters["ChoralHealthBuff"] = nil
            #expect(rebuilt.player.globalInfo == counters, "\(turn): counters")
            #expect(rebuilt.player.hand.isEmpty)
        }
    }

    @Test(
        "Full game turn 11: run through the preview runner, the end-of-recruit preview against the unchanged board gives the combat's odds",
        .enabled(if: Fixtures.isAvailable(Fixtures.fullGame), "private fixture log not present"),
        .timeLimit(.simulationWait)
    )
    @MainActor
    func turn11Odds() async throws {
        // Replayed off the main actor, which the other runner tests share.
        let replay = try await Task.detached { try Self.replay(Fixtures.fullGame) }.value
        let pair = try #require(replay.pairs.first { $0.combat.bgTurn == 11 })
        var preview = pair.preview
        preview.input?.opponentBoard = pair.combat.input.opponentBoard
        // Seeded like the golden run: the committed input, so exactly `CombatOddsGoldenTests`'s odds.
        let simulator = try CombatGoldens.makeSimulator()
        let runner = OddsPreviewRunner(
            simulate: { input, budget, progress in
                try await simulator.simulate(input, budget: budget, seed: CombatGoldens.seed, progress: progress)
            },
            debounce: .milliseconds(10), budget: .golden
        )
        runner.update(preview)
        let odds = try await OddsPreviewRunnerTests.waitForFinal(runner)
        CombatOddsGoldenTests.expectFullGameTurn11(odds)
    }
}
