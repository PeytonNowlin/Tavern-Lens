import EntityStore
import PowerParser

/// What is known about one solo Battlegrounds game.
public struct BGGameRecord: Codable, Hashable, Sendable {
    public var gameType: String
    public var gameSeed: Int?
    public var buildNumber: Int?
    public var localPlayerID: Int?
    /// The last hero the local player held (the pick, once made).
    public var localHeroCardID: String?
    /// The `PowerTaskList` `CREATE_GAME` line.
    public var start: LogPosition
    /// The `GameEntity STATE=COMPLETE` line, or the local concede if that came first; nil while
    /// in progress or when the log was cut off.
    public var end: LogPosition?
    /// The latest BG turn reached; final once the game has ended.
    public var bgTurn: Int
    /// The local player's final place, set once when the game ends; nil while in progress.
    public var placement: Int?
    /// Where `placement` came from; `.concedeEstimate` marks it as estimated.
    public var placementSource: BGPlacementSource?
}

/// The event-driven history layer over the entity store: which solo Battlegrounds
/// games happened, when each started and ended and where the local player placed,
/// and what the current game's lobby has revealed (last-seen boards, opponent names).
///
/// Feed it every `EntityChange` with the store as it is after the change, every
/// `PowerEvent` after the store applied it (for player-name references), and call
/// `refresh` at batch boundaries so projected fields stay current.
public struct BGGameHistory: Sendable {
    public private(set) var games: [BGGameRecord] = []
    /// Index into `games` of the store's current game, when that game is solo Battlegrounds.
    public private(set) var currentIndex: Int?
    /// What the current game's lobby has revealed; empty outside a solo Battlegrounds game.
    public private(set) var lobby = BGLobbyMemory()

    /// Game entity `TURN` when the latest recruit phase started (the shopping-turn guard).
    private var shoppingStartTurn = 0
    /// Game entity `TURN` of the latest combat snapshot, so each combat is captured once.
    private var snapshotTurn = 0
    /// Names the bartender slot went by outside combat (placeholder, Bob's skin); never an opponent's.
    private var slotNames: Set<String> = []
    /// Set once the local player concedes: the hero's place at that moment.
    private var concede: Concede?

    private struct Concede: Sendable {
        var placeAtConcede: Int?
    }

    public init() {}

    public var current: BGGameRecord? { currentIndex.map { games[$0] } }

    public mutating func observe(_ change: EntityChange, in store: EntityStore, at position: LogPosition) {
        switch change {
        case .gameCreated:
            currentIndex = nil
            lobby = BGLobbyMemory()
            shoppingStartTurn = 0
            snapshotTurn = 0
            slotNames = []
            concede = nil
            if let snapshot = BGSnapshot.project(store) {
                games.append(BGGameRecord(
                    gameType: snapshot.gameType,
                    gameSeed: nil,
                    buildNumber: snapshot.buildNumber,
                    localPlayerID: nil,
                    localHeroCardID: nil,
                    start: position,
                    end: nil,
                    bgTurn: 0
                ))
                currentIndex = games.count - 1
            }
        case .tagChanged(let entityID, .state, _, .name("COMPLETE")) where entityID == store.gameEntityID:
            refresh(from: store)
            if let index = currentIndex, games[index].end == nil {
                games[index].end = position
                if games[index].placement == nil {
                    games[index].placement = Self.localPlace(store)
                    games[index].placementSource = games[index].placement.map { _ in .final }
                }
            }
        case .tagChanged(let entityID, .turn, _, .int(let turn)) where entityID == store.gameEntityID:
            if turn % 2 == 1 { shoppingStartTurn = turn }
        case .tagChanged(let entityID, .bgBattleStarting, .int(1), .int(0)) where entityID == store.gameEntityID:
            captureOpponentBoard(store, at: position)
        case .tagChanged(let entityID, .playerConcededOrDisconnected, _, .int(1)),
             .tagChanged(let entityID, .playerConcededOrDisconnectedByName, _, .int(1)),
             .tagChanged(let entityID, .playState, _, .name("CONCEDED")):
            if entityID == store.localPlayer?.entityID {
                localConceded(store, at: position)
            }
        default:
            break
        }
    }

    /// Learns opponent display names from player-name references to the bartender slot.
    ///
    /// The slot is printed under a placeholder, then Bob's skin during recruit, and under
    /// the current opponent's name during combat. The rename comes a few lines before
    /// `BACON_CURRENT_COMBAT_PLAYER_ID` is set (on a line naming the slot by its new
    /// name), so names are told apart by phase, and bound once the opponent is known.
    /// Call after the store applied `event`.
    public mutating func observe(_ event: PowerEvent, in store: EntityStore) {
        guard currentIndex != nil, case .tagChange(.playerName(let name), _) = event,
              let local = store.localPlayer, let slot = store.otherPlayer,
              store.metadata.playerNames[local.playerID] != name,
              !lobby.displayNames.values.contains(name)
        else { return }
        let turn = store.gameEntity?.int(.turn) ?? 0
        guard BGPhase(turn: turn) == .combat,
              !slotNames.contains(name), store.metadata.playerNames[slot.playerID] != name
        else {
            slotNames.insert(name)
            return
        }
        if let opponent = BGSnapshot.combatOpponent(store), lobby.displayNames[opponent] == nil {
            lobby.displayNames[opponent] = name
        }
    }

    /// At the tag 2022 1→0 edge both boards are final and nothing has attacked yet.
    /// The edge counts only after a recruit phase has ended (the shopping-turn guard),
    /// once per combat.
    private mutating func captureOpponentBoard(_ store: EntityStore, at position: LogPosition) {
        guard currentIndex != nil, let turn = store.gameEntity?.int(.turn),
              turn > shoppingStartTurn, turn != snapshotTurn,
              let opponent = BGSnapshot.combatOpponent(store), let slot = store.otherPlayer
        else { return }
        snapshotTurn = turn
        let hero = store[slot.entityID]?.int(.heroEntity).flatMap { store[$0] }
        lobby.lastSeenBoards[opponent] = BGOpponentBoard(
            playerID: opponent,
            bgTurn: (turn + 1) / 2,
            heroCardID: hero.map(\.cardID).flatMap { $0.isEmpty ? nil : $0 },
            cards: BGCard.cards(in: store, controller: slot.playerID, zone: "PLAY") { kind, _ in kind == .minion },
            position: position
        )
    }

    /// A concede ends the game for the local player; the client may never log
    /// `STATE=COMPLETE` for it. The placement is marked as estimated.
    private mutating func localConceded(_ store: EntityStore, at position: LogPosition) {
        guard let index = currentIndex, concede == nil, games[index].placementSource != .final else { return }
        concede = Concede(placeAtConcede: Self.localPlace(store))
        refresh(from: store)
        if games[index].end == nil { games[index].end = position }
        games[index].placementSource = .concedeEstimate
        games[index].placement = Self.concedePlace(store, placeAtConcede: concede?.placeAtConcede)
    }

    /// The local hero's place if the client updated it after the concede, else the lowest
    /// place still open: one below every other hero still alive.
    static func concedePlace(_ store: EntityStore, placeAtConcede: Int?) -> Int? {
        let place = localPlace(store)
        if let place, place != placeAtConcede { return place }
        guard let snapshot = BGSnapshot.project(store) else { return place }
        return 1 + snapshot.lobby.filter { !$0.isLocal && !$0.isDead }.count
    }

    /// `PLAYER_LEADERBOARD_PLACE` on the local Player's `HERO_ENTITY`.
    static func localPlace(_ store: EntityStore) -> Int? {
        guard let local = store.localPlayer, let heroID = store[local.entityID]?.int(.heroEntity) else { return nil }
        return store[heroID]?.int(.playerLeaderboardPlace)
    }

    public mutating func refresh(from store: EntityStore) {
        guard let index = currentIndex, let snapshot = BGSnapshot.project(store) else { return }
        var record = games[index]
        record.gameSeed = snapshot.gameSeed ?? record.gameSeed
        record.buildNumber = snapshot.buildNumber ?? record.buildNumber
        record.localPlayerID = snapshot.localPlayerID ?? record.localPlayerID
        record.localHeroCardID = snapshot.localHero?.cardID ?? record.localHeroCardID
        record.bgTurn = max(record.bgTurn, snapshot.bgTurn)
        // After a concede the client may still write the real place; take it once it differs.
        if let concede, record.placementSource == .concedeEstimate {
            record.placement = Self.concedePlace(store, placeAtConcede: concede.placeAtConcede)
        }
        games[index] = record
    }
}
