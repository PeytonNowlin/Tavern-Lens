import PowerParser

/// What the overlay and menu bar show at one moment. This is the engine's output
/// and what golden tests compare, so it holds only what a player would see.
public struct ViewState: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Hashable, Sendable {
        /// No solo Battlegrounds game (none yet, or another mode is being played).
        case noGame
        case inGame
        case gameOver
    }

    public var status: Status
    public var game: GameView?

    public static let noGame = ViewState(status: .noGame, game: nil)

    public init(status: Status, game: GameView?) {
        self.status = status
        self.game = game
    }
}

/// The solo Battlegrounds game on screen.
public struct GameView: Codable, Hashable, Sendable {
    public var gameType: String
    public var localPlayerID: Int?
    /// Card ID of the local hero; nil until the hero pick resolves.
    public var localHeroCardID: String?
    /// The Battlegrounds turn (0 before the first recruit phase).
    public var bgTurn: Int

    public init(gameType: String, localPlayerID: Int?, localHeroCardID: String?, bgTurn: Int) {
        self.gameType = gameType
        self.localPlayerID = localPlayerID
        self.localHeroCardID = localHeroCardID
        self.bgTurn = bgTurn
    }
}

/// A view state and the log position where it took effect.
public struct TimelineEntry: Codable, Hashable, Sendable {
    public var position: LogPosition
    public var state: ViewState

    public init(position: LogPosition, state: ViewState) {
        self.position = position
        self.state = state
    }
}
