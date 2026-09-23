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
    public var outcome: BGGameOutcome = .inProgress
    /// Each time the game was resent after a disconnect or a client restart.
    public var reconnects: [BGReconnect] = []

    public init(
        gameType: String, gameSeed: Int?, buildNumber: Int?, localPlayerID: Int?, localHeroCardID: String?,
        start: LogPosition, end: LogPosition? = nil, bgTurn: Int, placement: Int? = nil,
        placementSource: BGPlacementSource? = nil, outcome: BGGameOutcome = .inProgress, reconnects: [BGReconnect] = []
    ) {
        self.gameType = gameType
        self.gameSeed = gameSeed
        self.buildNumber = buildNumber
        self.localPlayerID = localPlayerID
        self.localHeroCardID = localHeroCardID
        self.start = start
        self.end = end
        self.bgTurn = bgTurn
        self.placement = placement
        self.placementSource = placementSource
        self.outcome = outcome
        self.reconnects = reconnects
    }
}

/// The event-driven history layer over the entity store: which solo Battlegrounds
/// games happened, when each started and ended and where the local player placed,
/// and what the current game's lobby has revealed (last-seen boards, opponent names).
///
/// Games are identified by `GAME_SEED`. A `CREATE_GAME` whose seed matches a game still
/// in progress is a reconnect: the game's record and journal carry on, and the lobby
/// memory is kept. Any other `CREATE_GAME` leaves the games in progress `abandoned`.
/// A game from an earlier log (the client restarted mid-game) can be carried in with
/// `resume(_:journal:)`.
///
/// Feed it every `EntityChange` with the store as it is after the change, every
/// `PowerEvent` after the store applied it (for player-name references), and call
/// `refresh` at batch boundaries so projected fields stay current.
public struct BGGameHistory: Sendable {
    public private(set) var games: [BGGameRecord] = []
    /// Per-turn snapshots, boards seen and names of each game in `games`, by the same index.
    public private(set) var journals: [BGGameJournal] = []
    /// Index into `games` of the store's current game, when that game is solo Battlegrounds.
    public private(set) var currentIndex: Int?
    /// Indices of games whose record or journal reached a checkpoint (started, reconnected,
    /// a turn ended, a board was seen, ended, abandoned) since `clearChangedGames()`.
    public private(set) var changedGames: Set<Int> = []
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
    /// The store's `CREATE_GAME`, until its game entity (and seed) says which game it is.
    private var pendingCreate: PendingCreate?

    private struct PendingCreate: Sendable {
        var position: LogPosition
        var previousIndex: Int?
    }

    private struct Concede: Sendable {
        var placeAtConcede: Int?
    }

    public init() {}

    public var current: BGGameRecord? { currentIndex.map { games[$0] } }

    /// The current game's journal.
    public var currentJournal: BGGameJournal? { currentIndex.map { journals[$0] } }

    public mutating func clearChangedGames() {
        changedGames = []
    }

    /// Carries in a game still in progress from an earlier log, so that a `CREATE_GAME`
    /// with its seed resumes it (keeping its boards seen and names) rather than starting
    /// a new game. Ignored unless it's in progress, has a seed and isn't known already.
    public mutating func resume(_ record: BGGameRecord, journal: BGGameJournal) {
        guard record.outcome == .inProgress, let seed = record.gameSeed,
              !games.contains(where: { $0.gameSeed == seed })
        else { return }
        games.append(record)
        journals.append(journal)
    }

    public mutating func observe(_ change: EntityChange, in store: EntityStore, at position: LogPosition) {
        switch change {
        case .gameCreated:
            pendingCreate = PendingCreate(position: position, previousIndex: currentIndex)
            currentIndex = nil
        case .entityCreated(let id) where id == store.gameEntityID && pendingCreate != nil:
            identifyGame(store)
        case .tagChanged(let entityID, .state, _, .name("COMPLETE")) where entityID == store.gameEntityID:
            refresh(from: store)
            if let index = currentIndex, games[index].end == nil {
                games[index].end = position
                games[index].outcome = .complete
                if games[index].placement == nil {
                    games[index].placement = Self.localPlace(store)
                    games[index].placementSource = games[index].placement.map { _ in .final }
                }
                journals[index].finalLobby = BGSnapshot.project(store)?.lobby
                changedGames.insert(index)
            }
        case .tagChanged(let entityID, .turn, _, .int(let turn)) where entityID == store.gameEntityID:
            if turn % 2 == 1 {
                shoppingStartTurn = turn
            } else {
                recordTurn(store, endOfRecruit: turn / 2, at: position)
            }
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
        if let index = currentIndex { journals[index].lastPosition = position }
    }

    /// Decides what the store's new game is, once its game entity (with `GAME_SEED`) exists:
    /// a reconnect of a game in progress, a new solo Battlegrounds game, or neither.
    private mutating func identifyGame(_ store: EntityStore) {
        guard let pending = pendingCreate else { return }
        pendingCreate = nil
        let seed = store.gameEntity?.int(.gameSeed)
        let turn = store.gameEntity?.int(.turn) ?? 0
        guard let snapshot = BGSnapshot.project(store) else {
            abandonGames(except: nil)
            return
        }
        if let seed, let index = games.lastIndex(where: { $0.gameSeed == seed && $0.outcome == .inProgress }) {
            let acrossSessions = index != pending.previousIndex
            if acrossSessions {
                // Carried in from an earlier log: its lobby memory comes from the journal.
                resetGameState()
                lobby = journals[index].lobbyMemory
                snapshotTurn = (journals[index].boardsSeen.map(\.bgTurn).max() ?? 0) * 2
            }
            // Reading a log again (the app restarted mid-game) meets `CREATE_GAME`s the
            // record already has; only a new one is a reconnect.
            let isKnown = pending.position == games[index].start
                || games[index].reconnects.contains { $0.resumedAt == pending.position }
            if !isKnown {
                games[index].reconnects.append(BGReconnect(
                    lastBefore: journals[index].lastPosition ?? games[index].start,
                    resumedAt: pending.position,
                    acrossSessions: acrossSessions
                ))
            }
            abandonGames(except: index)
            currentIndex = index
        } else {
            abandonGames(except: nil)
            resetGameState()
            games.append(BGGameRecord(
                gameType: snapshot.gameType,
                gameSeed: seed,
                buildNumber: snapshot.buildNumber,
                localPlayerID: nil,
                localHeroCardID: nil,
                start: pending.position,
                end: nil,
                bgTurn: 0
            ))
            journals.append(BGGameJournal())
            currentIndex = games.count - 1
        }
        // Joining at a later turn (a reconnect, or a late attach): the shopping-turn guard
        // starts from the turn the game is at.
        if turn > 0 { shoppingStartTurn = max(shoppingStartTurn, turn % 2 == 1 ? turn : turn - 1) }
        if let index = currentIndex { changedGames.insert(index) }
    }

    private mutating func resetGameState() {
        lobby = BGLobbyMemory()
        shoppingStartTurn = 0
        snapshotTurn = 0
        slotNames = []
        concede = nil
    }

    /// Every game still in progress, other than `kept`, never ended: a different game started.
    private mutating func abandonGames(except kept: Int?) {
        for index in games.indices where index != kept && games[index].outcome == .inProgress {
            games[index].outcome = .abandoned
            changedGames.insert(index)
        }
    }

    /// The end of a recruit phase: `TURN` just turned even, and the board, gold and
    /// lobby are still the recruit phase's.
    private mutating func recordTurn(_ store: EntityStore, endOfRecruit bgTurn: Int, at position: LogPosition) {
        guard let index = currentIndex, bgTurn > 0, let snapshot = BGSnapshot.project(store),
              let local = snapshot.local
        else { return }
        // One snapshot per turn, even when a log is read again.
        journals[index].turns.removeAll { $0.bgTurn == bgTurn }
        journals[index].turns.append(BGTurnSnapshot(
            bgTurn: bgTurn,
            position: position,
            hero: local.hero,
            gold: local.gold,
            tier: local.tier,
            board: local.board,
            lobby: snapshot.lobby,
            nextOpponentPlayerID: snapshot.nextOpponentPlayerID
        ))
        journals[index].turns.sort { $0.bgTurn < $1.bgTurn }
        changedGames.insert(index)
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
        if let opponent = BGSnapshot.combatOpponent(store), lobby.displayNames[opponent] == nil,
           let index = currentIndex {
            lobby.displayNames[opponent] = name
            journals[index].displayNames[opponent] = name
            changedGames.insert(index)
        }
    }

    /// At the tag 2022 1→0 edge both boards are final and nothing has attacked yet.
    /// The edge counts only after a recruit phase has ended (the shopping-turn guard),
    /// once per combat.
    private mutating func captureOpponentBoard(_ store: EntityStore, at position: LogPosition) {
        guard let index = currentIndex, let turn = store.gameEntity?.int(.turn),
              turn > shoppingStartTurn, turn != snapshotTurn,
              let opponent = BGSnapshot.combatOpponent(store), let slot = store.otherPlayer
        else { return }
        snapshotTurn = turn
        let hero = store[slot.entityID]?.int(.heroEntity).flatMap { store[$0] }
        let board = BGOpponentBoard(
            playerID: opponent,
            bgTurn: (turn + 1) / 2,
            heroCardID: hero.map(\.cardID).flatMap { $0.isEmpty ? nil : $0 },
            cards: BGCard.cards(in: store, controller: slot.playerID, zone: "PLAY") { kind, _ in kind == .minion },
            position: position
        )
        lobby.lastSeenBoards[opponent] = board
        // One board per opponent per combat, even when a log is read again.
        journals[index].boardsSeen.removeAll { $0.playerID == opponent && $0.bgTurn == board.bgTurn }
        journals[index].boardsSeen.append(board)
        changedGames.insert(index)
    }

    /// A concede ends the game for the local player; the client may never log
    /// `STATE=COMPLETE` for it. The placement is marked as estimated.
    private mutating func localConceded(_ store: EntityStore, at position: LogPosition) {
        guard let index = currentIndex, concede == nil, games[index].placementSource != .final else { return }
        concede = Concede(placeAtConcede: Self.localPlace(store))
        refresh(from: store)
        if games[index].end == nil { games[index].end = position }
        games[index].outcome = .conceded
        games[index].placementSource = .concedeEstimate
        games[index].placement = Self.concedePlace(store, placeAtConcede: concede?.placeAtConcede)
        journals[index].finalLobby = BGSnapshot.project(store)?.lobby
        changedGames.insert(index)
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
        guard record != games[index] else { return }
        // After the end only the placement can still move (a concede's estimate); save that.
        if record.end != nil { changedGames.insert(index) }
        games[index] = record
    }
}
