import Testing
import TavernEngine

/// Seam 1 on synthetic logs: the lobby, next opponent, last-seen boards, opponent names,
/// final placement and concede, covered without the private fixtures.
@Suite("Lobby and opponents on synthetic logs")
struct LobbySyntheticTests {
    static let local = SyntheticLog.localPlayerID
    static let opponentName = "Some Opponent"
    static let board: [SyntheticLog.Minion] = [
        .init(id: 700, cardID: "BG_Taunter", atk: 3, health: 4, extra: ["TAUNT=1"]),
        .init(id: 701, cardID: "BG_Gold_G", atk: 6, health: 2, extra: ["PREMIUM=1", "DIVINE_SHIELD=1"]),
    ]

    /// Hero picked, seven opponents in the lobby, first recruit phase with P3 next.
    static func lobbyGame(localPlace: Int = 3) -> SyntheticLog {
        var log = SyntheticLog()
        log.createGame(gameType: "GT_BATTLEGROUNDS")
        log.pickHero()
        log.sevenOpponents(localPlace: localPlace)
        log.localTag("NEXT_OPPONENT_PLAYER_ID", "3")
        log.turn(1)
        log.slotTag("NUM_TURNS_IN_PLAY", "1")  // Bob's name during recruit
        log.endTaskList()
        return log
    }

    static func replay(_ log: SyntheticLog) -> ReplayResult {
        TavernEngine.replay(lines: log.lines)
    }

    static func lastGame(_ log: SyntheticLog) throws -> GameView {
        try #require(replay(log).timeline.last?.state.game)
    }

    static func entry(_ game: GameView, _ playerID: Int) throws -> LobbyEntryView {
        try #require(game.lobby.first { $0.playerID == playerID })
    }

    @Test("The lobby has every hero once, by place; combat copies, previews and the local death copy don't count")
    func lobbyDeduplicated() throws {
        var log = Self.lobbyGame()
        log.startCombat(bgTurn: 1, opponent: 3, name: Self.opponentName, heroID: 800, board: Self.board)
        // The local hero dies: the client makes a second local hero with a stale place.
        log.tag(SyntheticLog.pickedHeroID, "DAMAGE", "31")
        log.card(900, "TB_BaconShop_HERO_15", controller: Self.local, zone: "SETASIDE", position: 0, type: "HERO", health: 30,
                 extra: ["PLAYER_ID=\(Self.local)", "PLAYER_LEADERBOARD_PLACE=2"])
        log.endTaskList()

        let game = try Self.lastGame(log)
        #expect(game.lobby.count == 8)
        #expect(game.lobby.map(\.place) == Array(1...8).map(Optional.some))
        #expect(Set(game.lobby.map(\.playerID)).count == 8)
        let me = try Self.entry(game, Self.local)
        #expect(me.isLocal && me.isDead && me.place == 3)
        #expect(me.hero.hp == -1)
        #expect(me.heroCardID == "TB_BaconShop_HERO_15")
        #expect(game.lobby.filter(\.isLocal).count == 1)
        let opponent = try Self.entry(game, 3)
        #expect(opponent.heroCardID == "BG_HERO_3" && !opponent.isDead && opponent.tier == 1)
    }

    @Test("Hero health, armor, tier and triples follow each lobby hero's tags")
    func lobbyStats() throws {
        var log = Self.lobbyGame()
        log.tag(154, "DAMAGE", "12")
        log.tag(154, "ARMOR", "5")
        log.tag(154, "PLAYER_TECH_LEVEL", "4")
        log.tag(154, "PLAYER_TRIPLES", "2")
        log.endTaskList()

        let entry = try Self.entry(try Self.lastGame(log), 4)
        #expect(entry.hero == HeroStatsView(hp: 23, health: 30, damage: 12, armor: 5, triples: 2))
        #expect(entry.tier == 4)
    }

    @Test("The next opponent is the local Player's NEXT_OPPONENT_PLAYER_ID")
    func nextOpponent() throws {
        var log = Self.lobbyGame()
        var game = try Self.lastGame(log)
        #expect(game.nextOpponentPlayerID == 3)
        #expect(game.nextOpponent?.heroCardID == "BG_HERO_3")
        #expect(game.combatOpponentPlayerID == nil)

        log.startCombat(bgTurn: 1, opponent: 3, name: Self.opponentName, heroID: 800, board: Self.board)
        #expect(try Self.lastGame(log).combatOpponentPlayerID == 3)
        log.endCombat(board: Self.board, nextOpponent: 7)
        game = try Self.lastGame(log)
        #expect(game.nextOpponentPlayerID == 7)
        #expect(game.combatOpponentPlayerID == nil)
    }

    @Test("An opponent's board is captured at the tag 2022 1→0 edge, and kept after the combat")
    func lastSeenBoard() throws {
        var log = Self.lobbyGame()
        var game = try Self.lastGame(log)
        #expect(try Self.entry(game, 3).lastSeenBoard == nil)

        log.startCombat(bgTurn: 1, opponent: 3, name: Self.opponentName, heroID: 800, board: Self.board)
        // The fight changes the board after the snapshot.
        log.tag(700, "DAMAGE", "4")
        log.tag(701, "DIVINE_SHIELD", "0")
        log.card(702, "BG_Token", controller: SyntheticLog.slotPlayerID, zone: "PLAY", position: 3, atk: 1, health: 1)
        log.endTaskList()
        log.endCombat(board: Self.board, nextOpponent: 7)
        log.turn(3)

        game = try Self.lastGame(log)
        let seen = try #require(try Self.entry(game, 3).lastSeenBoard)
        #expect(seen.bgTurn == 1)
        #expect(seen.heroCardID == "BG_HERO_3")
        #expect(seen.cards.map(\.cardID) == ["BG_Taunter", "BG_Gold_G"])
        #expect(seen.cards.map(LocalPlayerFixtureTests.render) == ["3/4 T", "*6/2 DS"])
        // Only the opponent fought has a board; the local player never does.
        #expect(game.lobby.filter { $0.lastSeenBoard != nil }.map(\.playerID) == [3])
    }

    @Test("A later combat against the same opponent replaces the board and its turn")
    func lastSeenBoardReplaced() throws {
        var log = Self.lobbyGame()
        log.startCombat(bgTurn: 1, opponent: 3, name: Self.opponentName, heroID: 800, board: Self.board)
        log.endCombat(board: Self.board, nextOpponent: 3)
        log.turn(3)
        let later: [SyntheticLog.Minion] = [.init(id: 710, cardID: "BG_Big", atk: 9, health: 9)]
        log.startCombat(bgTurn: 2, opponent: 3, name: Self.opponentName, heroID: 810, board: later)

        let seen = try #require(try Self.entry(try Self.lastGame(log), 3).lastSeenBoard)
        #expect(seen.bgTurn == 2)
        #expect(seen.cards.map(\.cardID) == ["BG_Big"])
    }

    @Test("Shopping-turn guard: a 2022 1→0 edge inside a recruit phase captures nothing")
    func shoppingTurnGuard() throws {
        var log = Self.lobbyGame()
        // A spurious combat marker while shopping, with the slot's combat tag set.
        log.slotTag("BACON_CURRENT_COMBAT_PLAYER_ID", "3")
        log.card(720, "BG_Shop", controller: SyntheticLog.slotPlayerID, zone: "PLAY", position: 1, atk: 2, health: 2)
        log.gameTag("2022", "1")
        log.endTaskList()
        log.gameTag("2022", "0")
        log.endTaskList()
        log.slotTag("BACON_CURRENT_COMBAT_PLAYER_ID", "0")
        log.endTaskList()

        let game = try Self.lastGame(log)
        #expect(game.lobby.allSatisfy { $0.lastSeenBoard == nil })
    }

    @Test("An opponent's display name is learned in combat; Bob's and the placeholder names never are")
    func displayNames() throws {
        var log = Self.lobbyGame()
        #expect(try Self.lastGame(log).lobby.allSatisfy { $0.displayName == nil })

        log.startCombat(bgTurn: 1, opponent: 3, name: Self.opponentName, heroID: 800, board: Self.board)
        log.endCombat(board: Self.board, nextOpponent: 7)
        log.turn(3)
        // Bob's name during combat setup, before the rename, is not the next opponent's.
        log.turn(4)
        log.slotTag("NUM_TURNS_IN_PLAY", "2")
        log.endTaskList()
        log.startCombat(bgTurn: 2, opponent: 7, name: "Another Opponent", heroID: 810, board: [])

        let game = try Self.lastGame(log)
        #expect(try Self.entry(game, 3).displayName == Self.opponentName)
        #expect(try Self.entry(game, 7).displayName == "Another Opponent")
        #expect(try Self.entry(game, Self.local).displayName == nil)
        #expect(game.lobby.compactMap(\.displayName).count == 2)
    }

    @Test("The final placement is the local hero's place at STATE=COMPLETE, set once")
    func finalPlacement() throws {
        var log = Self.lobbyGame()
        log.startCombat(bgTurn: 1, opponent: 3, name: Self.opponentName, heroID: 800, board: Self.board)
        log.tag(SyntheticLog.pickedHeroID, "DAMAGE", "40")
        log.endTaskList()
        #expect(try Self.lastGame(log).placement == nil)

        log.tag(SyntheticLog.pickedHeroID, "PLAYER_LEADERBOARD_PLACE", "5")
        log.completeGame()
        // Events after COMPLETE don't move it.
        log.tag(SyntheticLog.pickedHeroID, "PLAYER_LEADERBOARD_PLACE", "2")
        log.endTaskList()

        let result = Self.replay(log)
        let game = try #require(result.games.only)
        #expect(game.placement == 5)
        #expect(game.placementSource == .final)
        let placements = result.timeline.map(\.state.game?.placement)
        let firstPlaced = try #require(placements.firstIndex { $0 != nil })
        #expect(result.timeline[firstPlaced].state.status == .gameOver)
        #expect(placements[firstPlaced...].allSatisfy { $0 == PlacementView(place: 5, isEstimated: false) })
        #expect(placements[..<firstPlaced].allSatisfy { $0 == nil })
    }

    @Test("A concede (tag 3479) ends the game with an estimated placement: the lowest place still open")
    func concedeEstimate() throws {
        var log = Self.lobbyGame(localPlace: 2)
        // Two opponents are already out.
        log.tag(151, "DAMAGE", "30")
        log.tag(152, "DAMAGE", "35")
        log.endTaskList()
        log.localTag("3479", "1")
        log.endTaskList()

        let result = Self.replay(log)
        let game = try #require(result.games.only)
        #expect(game.placement == 6)  // 1 + the 5 opponents still alive
        #expect(game.placementSource == .concedeEstimate)
        #expect(game.end != nil)
        let last = try #require(result.timeline.last)
        #expect(last.state.status == .gameOver)
        #expect(last.state.game?.placement == PlacementView(place: 6, isEstimated: true))
    }

    @Test("After a concede the client's own place is used once it changes, still marked estimated")
    func concedeClientPlace() throws {
        var log = Self.lobbyGame(localPlace: 2)
        log.localTag("PLAYSTATE", "CONCEDED")
        log.endTaskList()
        #expect(try Self.lastGame(log).placement == PlacementView(place: 8, isEstimated: true))

        log.tag(SyntheticLog.pickedHeroID, "PLAYER_LEADERBOARD_PLACE", "7")
        log.endTaskList()
        #expect(try Self.lastGame(log).placement == PlacementView(place: 7, isEstimated: true))
    }

    @Test("A concede-or-disconnect tag on the bartender slot is not the local player's concede")
    func slotConcedeIgnored() throws {
        var log = Self.lobbyGame()
        log.slotTag("3479", "1")
        log.endTaskList()
        let result = Self.replay(log)
        #expect(result.games.only?.placement == nil)
        #expect(result.timeline.last?.state.status == .inGame)
    }
}
