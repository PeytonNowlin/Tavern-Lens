/// What the menu-bar item says about live tracking.
public enum LiveStatus: Hashable, Sendable {
    /// Hearthstone isn't running.
    case waitingForHearthstone
    /// The log config was repaired while Hearthstone ran; nothing useful is logged until it restarts.
    case restartRequired
    /// Hearthstone runs but its session folder for this launch hasn't appeared yet.
    case waitingForLogs
    /// Following the logs; no solo Battlegrounds game is in progress.
    case watching(inBattlegroundsLobby: Bool)
    /// A solo Battlegrounds game is in progress.
    case tracking(bgTurn: Int)
    /// The last solo Battlegrounds game has ended.
    case gameOver(bgTurn: Int)

    /// Restart-required wins over everything but Hearthstone not running, because
    /// nothing else is trustworthy until the client restarts.
    public init(hearthstoneRunning: Bool, restartRequired: Bool, followingSession: Bool, view: ViewState, scene: String?) {
        if !hearthstoneRunning {
            self = .waitingForHearthstone
        } else if restartRequired {
            self = .restartRequired
        } else if !followingSession {
            self = .waitingForLogs
        } else {
            switch view.status {
            case .inGame: self = .tracking(bgTurn: view.game?.bgTurn ?? 0)
            case .gameOver: self = .gameOver(bgTurn: view.game?.bgTurn ?? 0)
            case .noGame: self = .watching(inBattlegroundsLobby: scene == "BACON")
            }
        }
    }

    public var title: String {
        switch self {
        case .waitingForHearthstone: "Waiting for Hearthstone"
        case .restartRequired: "Restart Hearthstone required"
        case .waitingForLogs: "Waiting for Hearthstone logs"
        case .watching(let lobby): lobby ? "In the Battlegrounds lobby" : "Watching Hearthstone — no Battlegrounds game"
        case .tracking(let turn): turn > 0 ? "Tracking game — Turn \(turn)" : "Tracking game — hero pick"
        case .gameOver(let turn): "Game over — Turn \(turn)"
        }
    }

    /// Whether tracking is live (for the menu-bar icon).
    public var isTracking: Bool {
        if case .tracking = self { true } else { false }
    }
}
