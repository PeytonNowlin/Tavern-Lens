import EntityStore
import PowerParser

/// Which kind of Battlegrounds game a `GameType` names.
public enum BattlegroundsMode: String, Codable, Hashable, Sendable {
    case solo
    case duos
    case notBattlegrounds

    /// From a `GameType` enum name (`GameState.DebugPrintGame`).
    /// Duos is recognised so it can be ignored; v1 tracks solo only.
    public init(gameType: String?) {
        switch gameType {
        case "GT_BATTLEGROUNDS", "GT_BATTLEGROUNDS_FRIENDLY", "GT_BATTLEGROUNDS_AI_VS_AI",
             "GT_BATTLEGROUNDS_PLAYER_VS_AI":
            self = .solo
        case let type? where type.hasPrefix("GT_BATTLEGROUNDS_DUO"):
            self = .duos
        default:
            self = .notBattlegrounds
        }
    }
}

/// A pure projection of the entity store onto the Battlegrounds state shown to the player.
///
/// Later layers add to it: the lobby and opponents next to `local`, and per-player
/// mechanics on `BGLocalPlayer` (and on each lobby entry).
public struct BGSnapshot: Hashable, Sendable {
    public var gameType: String
    public var gameSeed: Int?
    public var buildNumber: Int?
    public var localPlayerID: Int?
    /// `(TURN + 1) / 2` of the game entity: odd `TURN` is recruit, even is combat. 0 before turn 1.
    public var bgTurn: Int
    public var phase: BGPhase
    /// `GameEntity STATE == COMPLETE`.
    public var isComplete: Bool
    /// Nil until the Player entities exist.
    public var local: BGLocalPlayer?
    /// Bob's shop; empty outside the recruit phase.
    public var shop: BGShop
    /// Every lobby hero, one per PlayerID, ordered by leaderboard place.
    public var lobby: [BGLobbyEntry] = []
    /// The PlayerID the local player fights next (`NEXT_OPPONENT_PLAYER_ID`).
    public var nextOpponentPlayerID: Int?
    /// The PlayerID being fought right now; nil outside combat.
    public var combatOpponentPlayerID: Int?

    /// Nil until a hero is picked (the placeholder hero doesn't count).
    public var localHero: BGHeroState? { local?.hero }

    /// The hero every player holds before the hero pick resolves.
    static let placeholderHeroCardID = "TB_BaconShop_HERO_PH"

    /// Nil unless the store's current game is a solo Battlegrounds game.
    public static func project(_ store: EntityStore) -> BGSnapshot? {
        guard store.gamesCreated > 0,
              BattlegroundsMode(gameType: store.metadata.gameType) == .solo,
              let gameType = store.metadata.gameType
        else { return nil }

        let game = store.gameEntity
        let turn = game?.int(.turn) ?? 0
        let phase = BGPhase(turn: turn)
        let local = localPlayer(store)
        return BGSnapshot(
            gameType: gameType,
            gameSeed: game?.int(.gameSeed),
            buildNumber: store.metadata.buildNumber,
            localPlayerID: store.localPlayer?.playerID,
            bgTurn: (turn + 1) / 2,
            phase: phase,
            isComplete: game?.name(.state) == "COMPLETE",
            local: local,
            // `TURN` turns even a few task lists before the client clears the shop;
            // from then on the old shop is no longer for sale.
            shop: phase == .recruit ? shop(store) : .empty,
            lobby: lobby(store, local: local),
            nextOpponentPlayerID: nextOpponent(store),
            combatOpponentPlayerID: combatOpponent(store)
        )
    }

    static func localPlayer(_ store: EntityStore) -> BGLocalPlayer? {
        guard let slot = store.localPlayer else { return nil }
        let player = store[slot.entityID]
        var hero: BGHeroState?
        if let heroID = player?.int(.heroEntity), let entity = store[heroID],
           !entity.cardID.isEmpty, entity.cardID != placeholderHeroCardID {
            hero = BGHeroState(entity)
        }
        return BGLocalPlayer(
            playerID: slot.playerID,
            hero: hero,
            gold: BGGold(player),
            tier: hero?.tier ?? player?.int(.playerTechLevel),
            board: BGCard.cards(in: store, controller: slot.playerID, zone: "PLAY") { kind, _ in kind == .minion },
            // Hero-pick options sit in HAND until the pick resolves.
            hand: BGCard.cards(in: store, controller: slot.playerID, zone: "HAND") { _, type in type != "HERO" }
        )
    }

    /// The bartender slot's minions and tavern spells in `PLAY`, but only while it isn't
    /// fighting: during combat the same slot holds the opponent's board, and its
    /// `BACON_CURRENT_COMBAT_PLAYER_ID` is the opponent's PlayerID instead of 0.
    static func shop(_ store: EntityStore) -> BGShop {
        guard let slot = store.otherPlayer,
              (store[slot.entityID]?.int(.baconCurrentCombatPlayerID) ?? 0) == 0
        else { return .empty }
        let cards = BGCard.cards(in: store, controller: slot.playerID, zone: "PLAY") { _, type in
            type == "MINION" || type == "BATTLEGROUND_SPELL"
        }
        return BGShop(cards: cards)
    }
}
