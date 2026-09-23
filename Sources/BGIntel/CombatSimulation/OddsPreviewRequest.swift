import BGState
import EntityStore
import HSData

/// The recruit-phase odds preview: the local player's board as it is now against the next
/// opponent's last-seen board, as the simulator's input.
///
/// It is also the advisor's scoring seam: `input(withPlayer:)` / `input(withBoard:hand:)` put a
/// hypothetical board in place of the current one and keep everything else (the opponent, the
/// hero, the mechanics, the game state), so a candidate action can be simulated against the
/// same opponent.
public struct OddsPreviewRequest: Codable, Hashable, Sendable {
    public var gameSeed: Int?
    /// The BG turn of the recruit phase, and of the combat that follows it.
    public var bgTurn: Int
    /// The next opponent's lobby PlayerID.
    public var opponentPlayerID: Int
    /// The BG turn their board was last seen; nil when they haven't been fought yet.
    public var opponentSeenTurn: Int?
    /// Where the opponent's side came from.
    public var opponentSource: OpponentSource?
    /// Nil when there's no data: the next opponent hasn't been seen.
    public var input: BattleInput?
    /// Whether `input.gameState.validTribes` came from a tribe source; nil tribes mean every tribe.
    public var tribesKnown: Bool

    public enum OpponentSource: String, Codable, Hashable, Sendable {
        /// Their side of the combat-start input when they were last fought: exact, with enchantments,
        /// hand and mechanics (health and tier updated to now).
        case combatStart
        /// Rebuilt from the last-seen board in the game history (a game carried in from an earlier
        /// log): the minions as seen and the mechanics saved then, without enchantments or hand.
        case lastSeenBoard
    }

    public init(
        gameSeed: Int?, bgTurn: Int, opponentPlayerID: Int, opponentSeenTurn: Int?,
        opponentSource: OpponentSource?, input: BattleInput?
    ) {
        self.gameSeed = gameSeed
        self.bgTurn = bgTurn
        self.opponentPlayerID = opponentPlayerID
        self.opponentSeenTurn = opponentSeenTurn
        self.opponentSource = opponentSource
        self.input = input
        tribesKnown = input?.gameState.validTribes != nil
    }

    /// One preview per game, BG turn and opponent; the input within it changes as the board does.
    public var id: String { "\(gameSeed.map(String.init) ?? "-")/\(bgTurn)/P\(opponentPlayerID)" }

    public var hasData: Bool { input != nil }

    /// The same combat with another local side (a hypothetical board, hand, hero state); nil without data.
    public func input(withPlayer side: BattleBoard) -> BattleInput? {
        guard var input else { return nil }
        input.playerBoard = side
        return input
    }

    /// The same combat with another board (left to right) and, optionally, another hand; nil
    /// without data. Build the minions with `BattleInputBuilder.battleEntities(ids:in:)`.
    public func input(withBoard board: [BattleEntity], hand: [BattleEntity]? = nil) -> BattleInput? {
        guard var input else { return nil }
        input.playerBoard.board = board
        if let hand { input.playerBoard.player.hand = hand }
        return input
    }
}

extension BattleInputBuilder {
    /// The recruit-phase preview from the store now: the local side as it is, against `opponent`
    /// (their last-seen side, which the caller keeps), with the opponent's health and tier updated
    /// from the lobby. Nil outside recruit or without a next opponent.
    ///
    /// - Parameters:
    ///   - opponent: the next opponent's last-seen side and the turn it's from, or nil when they
    ///     haven't been seen (the request then has no data).
    public static func preview(
        store: EntityStore, snapshot: BGSnapshot, opponent: (side: BattleBoard, seenTurn: Int,
        source: OddsPreviewRequest.OpponentSource)?, validTribes: Set<HS.Race>?
    ) -> OddsPreviewRequest? {
        guard snapshot.phase == .recruit, let next = snapshot.nextOpponentPlayerID,
              next != snapshot.localPlayerID
        else { return nil }
        var input: BattleInput?
        if let opponent, let player = localSide(store: store, snapshot: snapshot) {
            var side = opponent.side
            if let entry = snapshot.lobby.first(where: { $0.playerID == next && !$0.isLocal }) {
                side.player.hpLeft = entry.hero.hp
                if let tier = entry.hero.tier, tier > 0 { side.player.tavernTier = tier }
            }
            input = Self.input(player: player, opponent: side, snapshot: snapshot, validTribes: validTribes)
        }
        return OddsPreviewRequest(
            gameSeed: snapshot.gameSeed, bgTurn: snapshot.bgTurn, opponentPlayerID: next,
            opponentSeenTurn: opponent?.seenTurn, opponentSource: opponent?.source, input: input
        )
    }
}
