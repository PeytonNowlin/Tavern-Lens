/// Builds small Power.log excerpts in the real line format, for tests that must run
/// without the private fixtures. Shapes are copied from the captured logs
/// (docs/research/log-validation-2026-09-22.md); names are made up.
struct SyntheticLog {
    static let localName = "Tester#0042"
    static let localPlayerID = 6
    static let slotPlayerID = 14
    static let gameEntityID = 16
    static let localPlayerEntityID = 17
    static let slotPlayerEntityID = 18
    static let placeholderHeroID = 27
    static let pickedHeroID = 108

    private(set) var lines: [String] = []
    var time = "21:09:40.3435500"

    // MARK: - Raw line kinds

    mutating func gameState(_ payload: String) {
        lines.append("D \(time) GameState.DebugPrintPower() - \(payload)")
    }

    mutating func printGame(_ payload: String) {
        lines.append("D \(time) GameState.DebugPrintGame() - \(payload)")
    }

    /// A `PowerTaskList.DebugPrintPower` line; `indent` mimics the client's (meaningless) indentation.
    mutating func power(_ payload: String, indent: Int = 4) {
        lines.append("D \(time) PowerTaskList.DebugPrintPower() - \(String(repeating: " ", count: indent))\(payload)")
    }

    mutating func endTaskList(_ n: Int = 1) {
        lines.append("D \(time) PowerProcessor.EndCurrentTaskList() - m_currentTaskList=\(n)")
    }

    mutating func raw(_ line: String) {
        lines.append(line)
    }

    // MARK: - Game-level pieces

    /// GameState's early `CREATE_GAME` + `DebugPrintGame`, then the synced `CREATE_GAME`.
    mutating func createGame(gameType: String, seed: Int = 1_172_082_863) {
        gameState("CREATE_GAME")
        printGame("BuildNumber=251952")
        printGame("GameType=\(gameType)")
        printGame("FormatType=FT_WILD")
        printGame("ScenarioID=3459")
        printGame("PlayerID=\(Self.localPlayerID), PlayerName=\(Self.localName)")
        printGame("PlayerID=\(Self.slotPlayerID), PlayerName=Bartender Placeholder")

        power("CREATE_GAME")
        power("GameEntity EntityID=\(Self.gameEntityID)")
        power("tag=CARDTYPE value=GAME", indent: 8)
        power("tag=ZONE value=PLAY", indent: 8)
        power("tag=GAME_SEED value=\(seed)", indent: 8)
        power("tag=2022 value=0", indent: 8)
        power("Player EntityID=\(Self.localPlayerEntityID) PlayerID=\(Self.localPlayerID) GameAccountId=[hi=144115193835963207 lo=506222026]")
        power("tag=CONTROLLER value=\(Self.localPlayerID)", indent: 8)
        power("tag=CARDTYPE value=PLAYER", indent: 8)
        power("tag=HERO_ENTITY value=\(Self.placeholderHeroID)", indent: 8)
        power("Player EntityID=\(Self.slotPlayerEntityID) PlayerID=\(Self.slotPlayerID) GameAccountId=[hi=0 lo=0]")
        power("tag=CONTROLLER value=\(Self.slotPlayerID)", indent: 8)
        power("tag=BACON_DUMMY_PLAYER value=1", indent: 8)
        power("FULL_ENTITY - Updating [entityName=BaconPHhero id=\(Self.placeholderHeroID) zone=PLAY zonePos=0 cardId=TB_BaconShop_HERO_PH player=\(Self.localPlayerID)] CardID=TB_BaconShop_HERO_PH")
        power("tag=CARDTYPE value=HERO", indent: 8)
        power("tag=ZONE value=PLAY", indent: 8)
        power("TAG_CHANGE Entity=GameEntity tag=STATE value=RUNNING ")
        power("TAG_CHANGE Entity=\(Self.localName) tag=PLAYSTATE value=PLAYING ")
        power("TAG_CHANGE Entity=Bartender Placeholder tag=PLAYSTATE value=PLAYING ")
        endTaskList()
    }

    /// The hero pick resolving: the chosen hero is created in HAND earlier and the
    /// Player's `HERO_ENTITY` moves to it. The hero's name has nested brackets and
    /// the bracket's zone is stale, as in real logs.
    mutating func pickHero(cardID: String = "TB_BaconShop_HERO_15") {
        power("FULL_ENTITY - Updating [entityName=Test Hero [DNT], the Brave id=\(Self.pickedHeroID) zone=HAND zonePos=1 cardId= player=\(Self.localPlayerID)] CardID=\(cardID)")
        power("tag=CARDTYPE value=HERO", indent: 12)
        power("tag=HEALTH value=30", indent: 4)
        power("tag=ZONE value=HAND")
        power("TAG_CHANGE Entity=\(Self.localName) tag=HERO_ENTITY value=\(Self.pickedHeroID) ")
        power("TAG_CHANGE Entity=[entityName=Test Hero [DNT], the Brave id=\(Self.pickedHeroID) zone=HAND zonePos=1 cardId=\(cardID) player=\(Self.localPlayerID)] tag=ZONE value=PLAY ")
        endTaskList()
    }

    /// Sets `GameEntity TURN`, the way both phases of a BG turn start.
    mutating func turn(_ value: Int) {
        power("TAG_CHANGE Entity=GameEntity tag=TURN value=\(value) ")
        endTaskList()
    }

    /// Plays BG turns 1...n (recruit and combat each).
    mutating func playTurns(_ bgTurns: Int) {
        for bgTurn in 1...bgTurns {
            turn(bgTurn * 2 - 1)
            turn(bgTurn * 2)
        }
    }

    /// Ends the game the way the client does, with the game entity referenced by bare id.
    mutating func completeGame() {
        power("TAG_CHANGE Entity=\(Self.localName) tag=PLAYSTATE value=LOST ")
        power("TAG_CHANGE Entity=Opponent Display Name tag=PLAYSTATE value=WON ")
        power("TAG_CHANGE Entity=\(Self.gameEntityID) tag=STATE value=COMPLETE ")
        endTaskList()
    }

    /// A whole solo game.
    static func soloGame(gameType: String = "GT_BATTLEGROUNDS", bgTurns: Int = 3, complete: Bool = true) -> SyntheticLog {
        var log = SyntheticLog()
        log.createGame(gameType: gameType)
        log.pickHero()
        log.playTurns(bgTurns)
        if complete { log.completeGame() }
        return log
    }
}
