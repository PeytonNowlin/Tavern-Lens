import EntityStore
import PowerParser

// Tags the lobby layer reads that the client prints by number. Their meaning comes
// from the research notes (log-validation, simulator-input-mapping, log-edge-cases §2)
// and may change on a patch.
extension GameTag {
    /// `BG_BATTLE_STARTING` on the game entity: its 1→0 edge is the moment both combat boards are final.
    static let bgBattleStarting = GameTag.id(2022)
    /// `TAG_PLAYER_CONCEDED_OR_DISCONNECTED`: 1 on the local Player when it concedes or leaves.
    static let playerConcededOrDisconnected = GameTag.id(3479)
    /// The same tag, should a later client print it by name before the enum table knows it.
    static let playerConcededOrDisconnectedByName = GameTag.unresolved("TAG_PLAYER_CONCEDED_OR_DISCONNECTED")
}

/// One lobby hero on the leaderboard.
public struct BGLobbyEntry: Codable, Hashable, Sendable {
    /// The player's lobby PlayerID (1–8), the hero's `PLAYER_ID`: the join key for
    /// next opponent, combat opponent, last-seen boards and names.
    public var playerID: Int
    public var hero: BGHeroState
    /// `PLAYER_LEADERBOARD_PLACE`; final once the hero is dead.
    public var place: Int?
    public var isLocal: Bool

    /// Dead at 0 HP or below (tag 1640 is unreliable).
    public var isDead: Bool { hero.hp <= 0 }
}

/// An opponent's board as it was at the start of a combat against them.
public struct BGOpponentBoard: Codable, Hashable, Sendable {
    public var playerID: Int
    /// The BG turn of the combat.
    public var bgTurn: Int
    /// The opponent's hero in that combat (the combat copy's card).
    public var heroCardID: String?
    /// Minions left to right. Entity IDs are not meaningful after the combat.
    public var cards: [BGCard]
    /// The line of the tag 2022 1→0 edge the board was captured at.
    public var position: LogPosition
    /// Their hero powers, trinkets, Deity, quests and counters at that moment; nil in
    /// records written before mechanics were tracked.
    public var mechanics: BGPlayerMechanics?
}

/// Where a game's final placement came from.
public enum BGPlacementSource: String, Codable, Hashable, Sendable {
    /// `PLAYER_LEADERBOARD_PLACE` on the local hero at `STATE=COMPLETE`.
    case final
    /// The local player conceded or left; the place may be the client's or estimated
    /// as the lowest place still open (log-edge-cases §2.3).
    case concedeEstimate
}

/// What the lobby has revealed over the current game: history the store alone can't
/// give once the combat is over.
public struct BGLobbyMemory: Hashable, Sendable {
    /// The latest board seen for each opponent, by PlayerID.
    public var lastSeenBoards: [Int: BGOpponentBoard] = [:]
    /// Opponents' display names by PlayerID, learned in combat. The bartender slot is
    /// printed under the current opponent's name only while fighting them.
    public var displayNames: [Int: String] = [:]

    public init() {}
}

extension BGSnapshot {
    /// Every lobby hero with a leaderboard place, one per PlayerID, ordered by place.
    ///
    /// The local entry is the Player's `HERO_ENTITY`: when the local hero dies the client
    /// creates a second copy with a stale place, which must not count. Opponents are the
    /// bartender slot's SETASIDE heroes with a place; the combat copy of an opponent's
    /// hero has no place, and the SETASIDE previews made at combat setup are under the
    /// local controller, so neither appears.
    static func lobby(_ store: EntityStore, local: BGLocalPlayer?) -> [BGLobbyEntry] {
        var entries: [BGLobbyEntry] = []
        let localPlayerID = local?.playerID
        if let local, let hero = local.hero, let entity = store[hero.entityID] {
            entries.append(BGLobbyEntry(
                playerID: local.playerID, hero: hero, place: entity.int(.playerLeaderboardPlace), isLocal: true
            ))
        }
        if let slot = store.otherPlayer {
            var byPlayer: [Int: Entity] = [:]
            for zone in ["SETASIDE", "GRAVEYARD"] {
                for entity in store.entities(controller: slot.playerID, zone: zone) {
                    guard entity.name(.cardType) == "HERO",
                          entity.int(.playerLeaderboardPlace) != nil,
                          let playerID = entity.int(.playerID), playerID > 0, playerID != localPlayerID,
                          entity.cardID != placeholderHeroCardID
                    else { continue }
                    // Should a player ever have two, the original (lowest ID) is the lobby hero.
                    if let existing = byPlayer[playerID], existing.id < entity.id { continue }
                    byPlayer[playerID] = entity
                }
            }
            for (playerID, entity) in byPlayer {
                entries.append(BGLobbyEntry(
                    playerID: playerID, hero: BGHeroState(entity), place: entity.int(.playerLeaderboardPlace),
                    isLocal: false
                ))
            }
        }
        return entries.sorted { ($0.place ?? .max, $0.playerID) < ($1.place ?? .max, $1.playerID) }
    }

    /// The bartender slot's `BACON_CURRENT_COMBAT_PLAYER_ID`: the opponent being fought, or nil outside combat.
    static func combatOpponent(_ store: EntityStore) -> Int? {
        guard let slot = store.otherPlayer, let id = store[slot.entityID]?.int(.baconCurrentCombatPlayerID), id > 0
        else { return nil }
        return id
    }

    /// The local Player's `NEXT_OPPONENT_PLAYER_ID`; known for the whole recruit phase.
    static func nextOpponent(_ store: EntityStore) -> Int? {
        guard let local = store.localPlayer, let id = store[local.entityID]?.int(.nextOpponentPlayerID), id > 0
        else { return nil }
        return id
    }
}
