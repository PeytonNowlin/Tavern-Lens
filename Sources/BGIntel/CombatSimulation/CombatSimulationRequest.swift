import PowerParser

/// A combat to simulate: the simulator's input for one combat, taken at its start
/// (the tag 2022 1→0 edge), before any Start of Combat effect.
public struct CombatSimulationRequest: Codable, Hashable, Sendable {
    public var gameSeed: Int?
    public var bgTurn: Int
    /// The opponent's lobby PlayerID.
    public var opponentPlayerID: Int
    /// The line of the 2022 1→0 edge.
    public var position: LogPosition
    public var input: BattleInput
    /// Whether `input.gameState.validTribes` came from a tribe provider; nil tribes mean every tribe.
    public var tribesKnown: Bool

    public init(gameSeed: Int?, bgTurn: Int, opponentPlayerID: Int, position: LogPosition, input: BattleInput) {
        self.gameSeed = gameSeed
        self.bgTurn = bgTurn
        self.opponentPlayerID = opponentPlayerID
        self.position = position
        self.input = input
        tribesKnown = input.gameState.validTribes != nil
    }

    /// Identifies the combat across republishes: one per game and BG turn.
    public var id: String { "\(gameSeed.map(String.init) ?? "-")/\(bgTurn)" }

    /// The local player's health going in, for the lethal warning.
    public var localHealth: Int { input.playerBoard.player.hpLeft }
}
