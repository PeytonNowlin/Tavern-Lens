import BGIntel
import SimulatorRuntime

/// What the combat odds panel shows for one combat: the request, and the simulator's
/// result so far. It starts without odds (simulating) and refines in place.
public struct CombatOddsView: Hashable, Sendable {
    /// `CombatSimulationRequest.id`: one per game and BG turn.
    public var requestID: String
    public var bgTurn: Int
    public var opponentPlayerID: Int
    /// Nil until the first partial result.
    public var odds: CombatOdds?
    /// Set when the simulation failed; the panel then says so instead of showing numbers.
    public var failure: String?

    public init(request: CombatSimulationRequest) {
        requestID = request.id
        bgTurn = request.bgTurn
        opponentPlayerID = request.opponentPlayerID
    }

    public var isFinal: Bool { odds?.isFinal == true || failure != nil }

    /// The chance this combat eliminates the local player, when it's above zero.
    public var lethalRisk: Double? { odds.flatMap { $0.lostLethal > 0 ? $0.lostLethal : nil } }

    /// The chance this combat eliminates the opponent, when it's above zero.
    public var lethalChance: Double? { odds.flatMap { $0.wonLethal > 0 ? $0.wonLethal : nil } }

    /// Whether this is for the combat on screen.
    public func isFor(_ game: GameView) -> Bool {
        game.phase == .combat && game.bgTurn == bgTurn && game.combatOpponentPlayerID.map { $0 == opponentPlayerID } != false
    }
}
