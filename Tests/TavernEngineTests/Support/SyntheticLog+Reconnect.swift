/// Reconnects for synthetic logs, in the shape log-edge-cases §3.1 describes: a new
/// `CREATE_GAME` with the same `GAME_SEED`, the game entity at the current `TURN`, and
/// every live entity resent as `FULL_ENTITY - Updating` with its current tags.
extension SyntheticLog {
    static let defaultSeed = 1_172_082_863

    /// The client resends the game after a disconnect. `metadata: false` leaves out the
    /// `DebugPrintGame` lines, which a reconnect may not print.
    mutating func reconnect(seed: Int = defaultSeed, turn: Int, metadata: Bool = true, localPlace: Int = 3) {
        gameState("CREATE_GAME")
        if metadata {
            printGame("BuildNumber=251952")
            printGame("GameType=GT_BATTLEGROUNDS")
            printGame("FormatType=FT_WILD")
            printGame("ScenarioID=3459")
            printGame("PlayerID=\(Self.localPlayerID), PlayerName=\(Self.localName)")
            printGame("PlayerID=\(Self.slotPlayerID), PlayerName=Bartender Placeholder")
        }
        power("CREATE_GAME")
        power("GameEntity EntityID=\(Self.gameEntityID)")
        power("tag=CARDTYPE value=GAME", indent: 8)
        power("tag=ZONE value=PLAY", indent: 8)
        power("tag=GAME_SEED value=\(seed)", indent: 8)
        power("tag=STATE value=RUNNING", indent: 8)
        power("tag=TURN value=\(turn)", indent: 8)
        power("tag=2022 value=0", indent: 8)
        power("Player EntityID=\(Self.localPlayerEntityID) PlayerID=\(Self.localPlayerID) GameAccountId=[hi=144115193835963207 lo=506222026]")
        power("tag=CONTROLLER value=\(Self.localPlayerID)", indent: 8)
        power("tag=CARDTYPE value=PLAYER", indent: 8)
        power("tag=HERO_ENTITY value=\(Self.pickedHeroID)", indent: 8)
        power("Player EntityID=\(Self.slotPlayerEntityID) PlayerID=\(Self.slotPlayerID) GameAccountId=[hi=0 lo=0]")
        power("tag=CONTROLLER value=\(Self.slotPlayerID)", indent: 8)
        power("tag=BACON_DUMMY_PLAYER value=1", indent: 8)
        card(
            Self.pickedHeroID, "TB_BaconShop_HERO_15", controller: Self.localPlayerID, zone: "PLAY", position: 0,
            type: "HERO", health: 30, extra: ["PLAYER_ID=\(Self.localPlayerID)", "PLAYER_LEADERBOARD_PLACE=\(localPlace)"]
        )
        let places = (1...8).filter { $0 != localPlace }
        for (index, playerID) in [1, 2, 3, 4, 5, 7, 8].enumerated() {
            lobbyHero(150 + playerID, "BG_HERO_\(playerID)", playerID: playerID, place: places[index])
        }
        endTaskList()
    }

    /// A different game in the same log: a new seed, through the hero pick.
    mutating func newGame(seed: Int) {
        createGame(gameType: "GT_BATTLEGROUNDS", seed: seed)
        pickHero()
    }
}
