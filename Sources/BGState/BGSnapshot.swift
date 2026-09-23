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

/// The local player's hero.
public struct HeroRef: Codable, Hashable, Sendable {
    public var entityID: Int
    public var cardID: String
}

/// A pure projection of the entity store onto the Battlegrounds state shown to the player.
public struct BGSnapshot: Hashable, Sendable {
    public var gameType: String
    public var gameSeed: Int?
    public var buildNumber: Int?
    public var localPlayerID: Int?
    /// Nil until a hero is picked (the placeholder hero doesn't count).
    public var localHero: HeroRef?
    /// `(TURN + 1) / 2` of the game entity: odd `TURN` is recruit, even is combat. 0 before turn 1.
    public var bgTurn: Int
    /// `GameEntity STATE == COMPLETE`.
    public var isComplete: Bool

    /// The hero every player holds before the hero pick resolves.
    static let placeholderHeroCardID = "TB_BaconShop_HERO_PH"

    /// Nil unless the store's current game is a solo Battlegrounds game.
    public static func project(_ store: EntityStore) -> BGSnapshot? {
        guard store.gamesCreated > 0,
              BattlegroundsMode(gameType: store.metadata.gameType) == .solo,
              let gameType = store.metadata.gameType
        else { return nil }

        let game = store.gameEntity
        let local = store.localPlayer
        var hero: HeroRef?
        if let local, let heroID = store[local.entityID]?.int(.heroEntity), let entity = store[heroID],
           !entity.cardID.isEmpty, entity.cardID != placeholderHeroCardID {
            hero = HeroRef(entityID: heroID, cardID: entity.cardID)
        }
        let turn = game?.int(.turn) ?? 0
        return BGSnapshot(
            gameType: gameType,
            gameSeed: game?.int(.gameSeed),
            buildNumber: store.metadata.buildNumber,
            localPlayerID: local?.playerID,
            localHero: hero,
            bgTurn: (turn + 1) / 2,
            isComplete: game?.name(.state) == "COMPLETE"
        )
    }
}
