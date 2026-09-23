import Testing
import TavernEngine

/// Seam 1 on synthetic logs, so the engine's behaviour is covered without the private fixtures.
@Suite("Replay of synthetic logs")
struct SyntheticReplayTests {
    @Test("A solo game is tracked from creation to completion")
    func soloGame() throws {
        let log = SyntheticLog.soloGame(bgTurns: 3)
        let result = TavernEngine.replay(lines: log.lines)

        let game = try #require(result.games.only)
        #expect(game.gameType == "GT_BATTLEGROUNDS")
        #expect(game.gameSeed == 1_172_082_863)
        #expect(game.localPlayerID == SyntheticLog.localPlayerID)
        #expect(game.localHeroCardID == "TB_BaconShop_HERO_15")
        #expect(game.bgTurn == 3)
        #expect(game.end != nil)
        #expect(game.start.line < game.end!.line)

        #expect(result.timeline.map(\.state.status).first == .inGame)
        #expect(result.timeline.last?.state.status == .gameOver)
        #expect(result.timeline.last?.state.game?.bgTurn == 3)
    }

    @Test("The hero is unknown until the pick replaces the placeholder")
    func heroPick() {
        let result = TavernEngine.replay(lines: SyntheticLog.soloGame(bgTurns: 1).lines)
        let heroes = result.timeline.map { $0.state.game?.localHeroCardID }
        #expect(heroes.first == .some(nil))
        #expect(heroes.last == "TB_BaconShop_HERO_15")
    }

    @Test("BG turn is (TURN + 1) / 2 and each turn appears in order", arguments: [1, 4, 12])
    func turns(bgTurns: Int) {
        let result = TavernEngine.replay(lines: SyntheticLog.soloGame(bgTurns: bgTurns, complete: false).lines)
        var shown: [Int] = []
        for turn in result.timeline.compactMap({ $0.state.game?.bgTurn }) where shown.last != turn {
            shown.append(turn)
        }
        #expect(shown == Array(0...bgTurns))
    }

    @Test(
        "Non-solo-Battlegrounds game types produce no BG game",
        arguments: ["GT_RANKED", "GT_CASUAL", "GT_ARENA", "GT_TAVERNBRAWL", "GT_BATTLEGROUNDS_DUO", "GT_UNKNOWN"]
    )
    func otherModesIgnored(gameType: String) {
        let result = TavernEngine.replay(lines: SyntheticLog.soloGame(gameType: gameType).lines)
        #expect(result.games.isEmpty)
        #expect(result.timeline.allSatisfy { $0.state == .noGame })
    }

    @Test("Other solo Battlegrounds game types are tracked", arguments: ["GT_BATTLEGROUNDS_FRIENDLY", "GT_BATTLEGROUNDS_PLAYER_VS_AI"])
    func otherSoloTypes(gameType: String) {
        let result = TavernEngine.replay(lines: SyntheticLog.soloGame(gameType: gameType).lines)
        #expect(result.games.map(\.gameType) == [gameType])
    }

    @Test("A game type seen in GameState before the synced CREATE_GAME applies to that game")
    func metadataPrecedesCreateGame() {
        // A BG game followed by a ranked game: the second game's metadata must not leak into the first.
        var log = SyntheticLog.soloGame(bgTurns: 2)
        log.createGame(gameType: "GT_RANKED")
        log.turn(1)
        let result = TavernEngine.replay(lines: log.lines)
        #expect(result.games.count == 1)
        #expect(result.games.first?.bgTurn == 2)
        #expect(result.timeline.last?.state == .noGame)
    }

    @Test("Two solo games in one log are two records")
    func twoGames() {
        var log = SyntheticLog.soloGame(bgTurns: 2)
        log.createGame(gameType: "GT_BATTLEGROUNDS", seed: 99)
        log.pickHero(cardID: "BG20_HERO_283")
        log.playTurns(1)
        let result = TavernEngine.replay(lines: log.lines)
        #expect(result.games.map(\.gameSeed) == [1_172_082_863, 99])
        #expect(result.games.map(\.localHeroCardID) == ["TB_BaconShop_HERO_15", "BG20_HERO_283"])
        #expect(result.games.map { $0.end != nil } == [true, false])
    }

    @Test("A log cut off mid-game, even mid-line, yields a game with no end")
    func truncated() throws {
        var log = SyntheticLog.soloGame(bgTurns: 2, complete: false)
        log.power("FULL_ENTITY - Updating [entityName=Zoatroid id=900 zone=PLAY zonePos=1 cardId=BG33_") // cut here
        let result = TavernEngine.replay(lines: log.lines)
        let game = try #require(result.games.only)
        #expect(game.end == nil)
        #expect(result.timeline.last?.state.status == .inGame)
        #expect(result.timeline.last?.state.game?.bgTurn == 2)
    }

    @Test("The early GameState stream never drives displayed state")
    func gameStateStreamIgnored() {
        var log = SyntheticLog()
        log.createGame(gameType: "GT_BATTLEGROUNDS")
        log.gameState("TAG_CHANGE Entity=16 tag=TURN value=5")  // GameState runs ahead of the animations
        log.gameState("TAG_CHANGE Entity=GameEntity tag=STATE value=COMPLETE")
        log.endTaskList()
        log.turn(1)
        let result = TavernEngine.replay(lines: log.lines)
        #expect(result.timeline.last?.state.game?.bgTurn == 1)
        #expect(result.timeline.last?.state.status == .inGame)
    }

    @Test("State is published at task-list boundaries, not mid-batch")
    func coalescedAtTaskListEnd() {
        var log = SyntheticLog()
        log.createGame(gameType: "GT_BATTLEGROUNDS")
        log.power("TAG_CHANGE Entity=GameEntity tag=TURN value=1 ")
        log.power("TAG_CHANGE Entity=GameEntity tag=TURN value=2 ")
        log.power("TAG_CHANGE Entity=GameEntity tag=TURN value=3 ")
        log.endTaskList()
        let result = TavernEngine.replay(lines: log.lines)
        #expect(result.timeline.compactMap { $0.state.game?.bgTurn } == [0, 2])
    }

    @Test("tag= lines attach to the most recent entity header, whatever their indentation")
    func tagLinesAttachToLastHeader() {
        var log = SyntheticLog()
        log.createGame(gameType: "GT_BATTLEGROUNDS")
        // A hero whose header and tags are at mismatched indents, created inside a block.
        log.power("BLOCK_START BlockType=TRIGGER Entity=GameEntity EffectCardId=System.Collections.Generic.List`1[System.String] EffectIndex=0 Target=0 SubOption=-1 TriggerKeyword=TAG_NOT_SET", indent: 0)
        log.power("FULL_ENTITY - Updating [entityName=UNKNOWN ENTITY [cardType=INVALID] id=300 zone=SETASIDE zonePos=0 cardId= player=6] CardID=BG20_HERO_283", indent: 8)
        log.power("tag=CARDTYPE value=HERO", indent: 4)
        log.power("tag=ZONE value=PLAY", indent: 12)
        log.power("BLOCK_END", indent: 0)
        log.power("TAG_CHANGE Entity=\(SyntheticLog.localName) tag=HERO_ENTITY value=300 ")
        log.endTaskList()
        let result = TavernEngine.replay(lines: log.lines)
        #expect(result.timeline.last?.state.game?.localHeroCardID == "BG20_HERO_283")
        #expect(result.diagnostics.parse.orphanTagLines == 0)
    }

    @Test("Only id is read from entity brackets; nested brackets and stale fields are tolerated")
    func bracketReferences() {
        var log = SyntheticLog()
        log.createGame(gameType: "GT_BATTLEGROUNDS")
        log.pickHero()
        // Stale zone/player fields and a bracketed name referencing the game entity by id.
        log.power("TAG_CHANGE Entity=[entityName=Weird [Name] [DNT], Prince of Things id=\(SyntheticLog.gameEntityID) zone=GRAVEYARD zonePos=9 cardId=NOPE player=3] tag=TURN value=7 ")
        log.endTaskList()
        let result = TavernEngine.replay(lines: log.lines)
        #expect(result.timeline.last?.state.game?.bgTurn == 4)
        #expect(result.diagnostics.parse.unreadableEntityRefs == 0)
    }

    @Test("Garbage and unknown lines never stop the replay")
    func tolerant() throws {
        var log = SyntheticLog()
        log.raw("")
        log.raw("\u{FFFD}\u{FFFD} not a log line")
        log.createGame(gameType: "GT_BATTLEGROUNDS")
        log.raw("D 21:09:41.1000000 PowerSpellController [taskListId=7].InitPowerSpell() - something")
        log.power("TAG_CHANGE Entity=GameEntity tag=SOME_FUTURE_TAG value=12 ")
        log.power("TAG_CHANGE Entity=GameEntity tag=9999 value=1 DEF CHANGE")
        log.power("META_DATA - Meta=HISTORY_TARGET Data=0 InfoCount=1")
        log.power("Info[0] = [entityName=Zoatroid id=40 zone=PLAY zonePos=1 cardId=BG33_000 player=6]", indent: 12)
        log.power("tag=ORPHAN value=1", indent: 8)
        log.turn(1)
        let result = TavernEngine.replay(lines: log.lines)
        let game = try #require(result.games.only)
        #expect(game.bgTurn == 1)
        #expect(result.diagnostics.parse.unparsableLines == 2)
        #expect(result.diagnostics.parse.orphanTagLines == 1)
    }
}
