/// Lobby heroes and combats for synthetic logs, in the order the captured logs print them
/// (docs/research/log-validation-2026-09-22.md, "Turn and phase boundaries").
extension SyntheticLog {
    /// A synthetic minion: `atk/health` plus extra tags (`"TAUNT=1"`, …).
    struct Minion {
        var id: Int
        var cardID: String
        var atk: Int
        var health: Int
        var extra: [String] = []
    }

    /// An opponent's lobby hero: bartender-controlled, in SETASIDE, with its lobby `PLAYER_ID`.
    mutating func lobbyHero(_ id: Int, _ cardID: String, playerID: Int, place: Int, damage: Int = 0, armor: Int = 0) {
        card(
            id, cardID, controller: Self.slotPlayerID, zone: "SETASIDE", position: 0, type: "HERO", health: 30,
            extra: ["PLAYER_ID=\(playerID)", "PLAYER_LEADERBOARD_PLACE=\(place)", "DAMAGE=\(damage)", "ARMOR=\(armor)", "PLAYER_TECH_LEVEL=1"]
        )
    }

    /// Seven opponents, PlayerIDs 1–5 and 7–8 (the local player is 6), with entity IDs
    /// 150 + PlayerID. Places fill 1…8 around the local hero's `localPlace`.
    mutating func sevenOpponents(localPlace: Int = 3) {
        tag(Self.pickedHeroID, "PLAYER_ID", String(Self.localPlayerID))
        tag(Self.pickedHeroID, "PLAYER_LEADERBOARD_PLACE", String(localPlace))
        let places = (1...8).filter { $0 != localPlace }
        for (index, playerID) in [1, 2, 3, 4, 5, 7, 8].enumerated() {
            lobbyHero(150 + playerID, "BG_HERO_\(playerID)", playerID: playerID, place: places[index])
        }
        endTaskList()
    }

    /// Combat setup and start against `opponent`, ending at the tag 2022 1→0 edge.
    ///
    /// The slot is renamed to the opponent's display name a few lines before its
    /// `BACON_CURRENT_COMBAT_PLAYER_ID` is set, and the opponent's hero and board are
    /// copies. A SETASIDE preview of the board under the local controller comes first.
    mutating func startCombat(bgTurn: Int, opponent: Int, name: String, heroID: Int, board: [Minion]) {
        turn(bgTurn * 2)
        gameTag("BOARD_VISUAL_STATE", "2")
        for minion in board {
            card(minion.id + 1000, minion.cardID, controller: Self.localPlayerID, zone: "SETASIDE", position: 0, atk: minion.atk, health: minion.health)
        }
        endTaskList()

        gameTag("2022", "1")
        slotTag("NUM_TURNS_IN_PLAY", "5", name: name)
        localTag("BACON_CURRENT_COMBAT_PLAYER_ID", String(Self.localPlayerID))
        slotTag("BACON_CURRENT_COMBAT_PLAYER_ID", String(opponent), name: name)
        card(heroID, "BG_HERO_\(opponent)", controller: Self.slotPlayerID, zone: "PLAY", position: 0, type: "HERO", health: 30, extra: ["PLAYER_ID=\(opponent)"])
        slotTag("HERO_ENTITY", String(heroID), name: name)
        for (index, minion) in board.enumerated() {
            card(minion.id, minion.cardID, controller: Self.slotPlayerID, zone: "PLAY", position: index + 1, atk: minion.atk, health: minion.health, extra: minion.extra + ["COPIED_FROM_ENTITY_ID=\(minion.id + 1000)"])
        }
        endTaskList()

        gameTag("2022", "0")
        endTaskList()
    }

    /// Combat over: the slot goes back to Bob, the copies leave, and the next opponent is announced.
    mutating func endCombat(board: [Minion], nextOpponent: Int) {
        gameTag("BOARD_VISUAL_STATE", "1")
        localTag("BACON_CURRENT_COMBAT_PLAYER_ID", "0")
        slotTag("BACON_CURRENT_COMBAT_PLAYER_ID", "0")
        for minion in board { tag(minion.id, "ZONE", "REMOVEDFROMGAME") }
        localTag("NEXT_OPPONENT_PLAYER_ID", String(nextOpponent))
        endTaskList()
    }
}
