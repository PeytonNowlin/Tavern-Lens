import Foundation
import HSLog
import Testing
import TavernEngine

/// Seam 1: the lobby and opponents in the captured games, checked against the per-turn
/// tables in docs/research/log-validation-2026-09-22.md. Skipped when the fixtures are absent.
@Suite("Lobby and opponents in captured games")
struct LobbyFixtureTests {
    /// One combat of the research table: the opponent's PlayerID and their board at
    /// tag 2022 1→0, as `ATK/HP` (health left), `*` = golden, then keywords.
    struct Combat: CustomStringConvertible {
        var bgTurn: Int
        var opponent: Int
        var board: [String]

        init(_ bgTurn: Int, opponent: Int, board: [String]) {
            self.bgTurn = bgTurn
            self.opponent = opponent
            self.board = board
        }

        var description: String { "BG turn \(bgTurn) vs P\(opponent)" }
    }

    static let fullGame: [Combat] = [
        Combat(1, opponent: 5, board: ["3/3"]),
        Combat(2, opponent: 2, board: ["2/1 T,R"]),
        Combat(3, opponent: 1, board: ["2/3 RALLY", "2/1 T,R", "0/2 T", "2/5"]),
        Combat(4, opponent: 8, board: ["5/7 RALLY", "3/4", "3/3", "5/8"]),
        Combat(5, opponent: 4, board: ["3/5 RALLY", "2/3 RALLY", "6/6", "2/5", "2/5 T,DR"]),
        Combat(6, opponent: 3, board: ["24/37", "3/3 RALLY", "2/3 RALLY", "3/4", "5/3 BC", "3/7"]),
        Combat(7, opponent: 7, board: ["3/4", "8/16", "6/9", "1/1 DR", "6/9 R,DR", "7/10 DR"]),
        Combat(8, opponent: 5, board: ["19/18", "*19/20 RALLY", "18/15 DS", "14/10 DS,R", "5/6", "13/15", "17/22"]),
        Combat(9, opponent: 2, board: ["55/72", "15/11 DR", "4/6 DR,BC", "6/8 DR,BC", "17/16 DS", "3/6", "3/1 DS"]),
        Combat(10, opponent: 8, board: ["67/59", "*95/82 T,DS,DR,RALLY", "*29/31 DS", "32/56", "18/14", "7/13", "20/22 DS"]),
        // N'raqi Sapper fires at Start of Combat, after the snapshot: its stats are pre-SoC.
        Combat(11, opponent: 7, board: ["43/21 DR,BC", "44/25 T,DR", "*58/43 T,R,DR", "46/30", "76/117", "75/112 T", "44/30 T,DR"]),
        Combat(12, opponent: 3, board: ["231/464 RALLY", "1967/3795", "*12/14 RALLY", "*6/14", "*14/28", "1/5"]),
    ]

    static let truncatedGame: [Combat] = [
        Combat(1, opponent: 6, board: ["1/4 RALLY"]),
        Combat(2, opponent: 3, board: ["3/3"]),
        Combat(3, opponent: 7, board: ["5/6 BC", "5/6 WF,BC"]),
        Combat(4, opponent: 5, board: ["3/5 BC", "3/8 T,BC", "1/4 T"]),
    ]

    @Test(
        "Next opponent and last-seen board: all 16 combats of both captures",
        .enabled(if: Fixtures.isAvailable(Fixtures.fullGame) && Fixtures.isAvailable(Fixtures.truncatedGame), "private fixture log not present")
    )
    func combats() throws {
        var checked = 0
        for (path, combats) in [(Fixtures.fullGame, Self.fullGame), (Fixtures.truncatedGame, Self.truncatedGame)] {
            let result = try FixtureReplays.result(path)
            for combat in combats {
                try expect(result.timeline, matches: combat)
                checked += 1
            }
        }
        #expect(checked == 16)
    }

    @Test(
        "Full game: 8 unique lobby entries from the hero pick to the end, after the local hero dies too",
        .enabled(if: Fixtures.isAvailable(Fixtures.fullGame), "private fixture log not present")
    )
    func lobbyStaysEight() throws {
        let result = try FixtureReplays.result(Fixtures.fullGame)
        let games = result.timeline.compactMap(\.state.game)
        let full = try #require(games.firstIndex { $0.lobby.count == 8 })
        #expect(games[full].phase == .heroPick)
        for game in games[full...] {
            #expect(game.lobby.count == 8, "BG turn \(game.bgTurn) \(game.phase)")
            #expect(Set(game.lobby.map(\.playerID)) == Set(1...8), "BG turn \(game.bgTurn) \(game.phase)")
            #expect(game.lobby.filter(\.isLocal).map(\.playerID) == [6])
        }

        let end = try #require(games.last)
        let me = try #require(end.lobby.first { $0.isLocal })
        #expect(me.isDead && me.place == 4 && me.hero.hp == -4)
        // Lobby at STATE=COMPLETE: (place, PlayerID, HP, tier, triples).
        #expect(end.lobby.map { [$0.place, $0.playerID, $0.hero.hp, $0.tier, $0.hero.triples] } == [
            [1, 7, 16, 4, 4], [2, 8, 15, 6, 3], [3, 3, 5, 5, 4], [4, 6, -4, 6, 2],
            [5, 1, -5, 6, 0], [6, 4, -2, 5, 1], [7, 2, -2, 5, 2], [8, 5, -8, 4, 2],
        ])
        #expect(end.lobby.filter(\.isDead).map(\.playerID) == [6, 1, 4, 2, 5])
    }

    @Test(
        "Full game: final placement 4th, set once at game end",
        .enabled(if: Fixtures.isAvailable(Fixtures.fullGame), "private fixture log not present")
    )
    func finalPlacement() throws {
        let result = try FixtureReplays.result(Fixtures.fullGame)
        let record = try #require(result.games.only)
        #expect(record.placement == 4)
        #expect(record.placementSource == .final)

        let placements = result.timeline.map(\.state.game?.placement)
        let first = try #require(placements.firstIndex { $0 != nil })
        #expect(result.timeline[first].state.status == .gameOver)
        #expect(placements[..<first].allSatisfy { $0 == nil })
        #expect(placements[first...].allSatisfy { $0 == PlacementView(place: 4, isEstimated: false) })
    }

    @Test(
        "Truncated game: no placement while the game is unfinished",
        .enabled(if: Fixtures.isAvailable(Fixtures.truncatedGame), "private fixture log not present")
    )
    func noPlacementWhenTruncated() throws {
        let result = try FixtureReplays.result(Fixtures.truncatedGame)
        #expect(result.games.only?.placement == nil)
        #expect(result.timeline.allSatisfy { $0.state.game?.placement == nil })
        let end = try #require(result.timeline.last?.state.game)
        #expect(end.lobby.count == 8)
        #expect(end.nextOpponentPlayerID == 8)
    }

    @Test(
        "Opponent names: every opponent fought is named, and the log binds that name to that PlayerID",
        .enabled(if: Fixtures.isAvailable(Fixtures.fullGame) && Fixtures.isAvailable(Fixtures.truncatedGame), "private fixture log not present")
    )
    func displayNames() throws {
        for (path, fought) in [(Fixtures.fullGame, Set([1, 2, 3, 4, 5, 7, 8])), (Fixtures.truncatedGame, Set([3, 5, 6, 7]))] {
            let result = try FixtureReplays.result(path)
            let lobby = try #require(result.timeline.last?.state.game?.lobby)
            let named = lobby.filter { $0.displayName != nil }
            #expect(Set(named.map(\.playerID)) == fought, "\(path)")
            #expect(Set(named.compactMap(\.displayName)).count == named.count, "names are distinct")
            #expect(lobby.first(where: \.isLocal)?.displayName == nil)
            #expect(named.allSatisfy { !$0.displayName!.contains("#") })

            // The log itself confirms each binding: the slot, under that name, gets the
            // opponent's PlayerID as its combat player. Names never leave this test.
            var bindings: Set<String> = []
            for line in try FixtureReplays.lines(path) {
                guard line.contains("PowerTaskList.DebugPrintPower()"), line.contains("tag=BACON_CURRENT_COMBAT_PLAYER_ID"),
                      let range = line.range(of: "TAG_CHANGE Entity=") else { continue }
                bindings.insert(String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces))
            }
            for entry in named {
                #expect(
                    bindings.contains("\(entry.displayName!) tag=BACON_CURRENT_COMBAT_PLAYER_ID value=\(entry.playerID)"),
                    "P\(entry.playerID)'s name is not the slot's name in its combat"
                )
            }
        }
    }

    // MARK: - Helpers

    private func expect(_ timeline: [TimelineEntry], matches combat: Combat, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let recruitEnd = try #require(
            GoldenHarness.Checkpoint.endOfPhase(combat.bgTurn, .recruit).select(from: timeline)?.state.game,
            "no recruit phase for \(combat)", sourceLocation: sourceLocation
        )
        #expect(recruitEnd.nextOpponentPlayerID == combat.opponent, "\(combat): next opponent", sourceLocation: sourceLocation)

        let combatGames = timeline.compactMap(\.state.game).filter { $0.bgTurn == combat.bgTurn && $0.phase == .combat }
        let fought = try #require(
            combatGames.first { $0.combatOpponentPlayerID != nil }, "\(combat): no combat opponent", sourceLocation: sourceLocation
        )
        #expect(fought.combatOpponentPlayerID == combat.opponent, "\(combat): combat opponent", sourceLocation: sourceLocation)

        // The board appears during this combat, belongs to the opponent fought, and is
        // the board at the 2022 1→0 edge.
        let captured = combatGames.compactMap { game in game.lobby.first { $0.lastSeenBoard?.bgTurn == combat.bgTurn } }
        let seen = try #require(captured.first, "\(combat): no board captured", sourceLocation: sourceLocation)
        #expect(seen.playerID == combat.opponent, "\(combat): board owner", sourceLocation: sourceLocation)
        let board = try #require(seen.lastSeenBoard, sourceLocation: sourceLocation)
        #expect(board.cards.map(LocalPlayerFixtureTests.render) == combat.board, "\(combat): board", sourceLocation: sourceLocation)
        #expect(board.heroCardID == seen.heroCardID, "\(combat): hero", sourceLocation: sourceLocation)

        // Kept, unchanged, to the next recruit phase.
        if let next = GoldenHarness.Checkpoint.startOfPhase(combat.bgTurn + 1, .recruit).select(from: timeline)?.state.game {
            #expect(
                next.lobby.first { $0.playerID == combat.opponent }?.lastSeenBoard == board,
                "\(combat): kept after combat", sourceLocation: sourceLocation
            )
        }
    }
}
