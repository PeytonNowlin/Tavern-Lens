import PowerParser

/// How a game ended, as far as the log shows.
public enum BGGameOutcome: String, Codable, Hashable, Sendable {
    /// Still being played, or the log stopped (the client quit or crashed) and nothing
    /// has decided the game's fate yet.
    case inProgress
    /// `GameEntity STATE=COMPLETE`: the placement is final.
    case complete
    /// The local player conceded or left; the placement may be estimated.
    case conceded
    /// The game never ended in the log: a later game with a different seed started
    /// instead. No placement.
    case abandoned
}

/// A reconnect: the game was resent under a new `CREATE_GAME` with the same `GAME_SEED`.
public struct BGReconnect: Codable, Hashable, Sendable {
    /// The last line seen of the game before the break.
    public var lastBefore: LogPosition
    /// The `CREATE_GAME` line that resumed it.
    public var resumedAt: LogPosition
    /// The game was resumed in another session's log (the client restarted), so the two
    /// positions are in different files.
    public var acrossSessions: Bool

    public init(lastBefore: LogPosition, resumedAt: LogPosition, acrossSessions: Bool) {
        self.lastBefore = lastBefore
        self.resumedAt = resumedAt
        self.acrossSessions = acrossSessions
    }
}

/// The state at the end of one recruit phase (the moment `TURN` turns even).
public struct BGTurnSnapshot: Codable, Hashable, Sendable {
    public var bgTurn: Int
    public var position: LogPosition
    /// The local hero; nil before the hero pick.
    public var hero: BGHeroState?
    public var gold: BGGold
    public var tier: Int?
    /// The local board, left to right.
    public var board: [BGCard]
    /// Every lobby hero, ordered by place.
    public var lobby: [BGLobbyEntry]
    public var nextOpponentPlayerID: Int?

    public init(
        bgTurn: Int, position: LogPosition, hero: BGHeroState?, gold: BGGold, tier: Int?, board: [BGCard],
        lobby: [BGLobbyEntry], nextOpponentPlayerID: Int?
    ) {
        self.bgTurn = bgTurn
        self.position = position
        self.hero = hero
        self.gold = gold
        self.tier = tier
        self.board = board
        self.lobby = lobby
        self.nextOpponentPlayerID = nextOpponentPlayerID
    }
}

/// Everything one game revealed over time, beyond its summary: what the store can't
/// give once the moment has passed. It is the part of a game's record that a reconnect
/// or a client restart must not lose.
public struct BGGameJournal: Codable, Hashable, Sendable {
    /// One snapshot per BG turn, at the end of its recruit phase.
    public var turns: [BGTurnSnapshot] = []
    /// Every opponent board seen, one per combat, in order.
    public var boardsSeen: [BGOpponentBoard] = []
    /// Opponents' display names, by PlayerID, learned in combat.
    public var displayNames: [Int: String] = [:]
    /// The lobby when the game ended for the local player.
    public var finalLobby: [BGLobbyEntry]?
    /// The latest line seen of this game.
    public var lastPosition: LogPosition?

    public init() {}

    /// What the lobby revealed, as the history layer keeps it for the current game.
    public var lobbyMemory: BGLobbyMemory {
        var memory = BGLobbyMemory()
        for board in boardsSeen { memory.lastSeenBoards[board.playerID] = board }
        memory.displayNames = displayNames
        return memory
    }
}
