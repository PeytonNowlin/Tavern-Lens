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
    /// The `GameEntity STATE=COMPLETE` line; nil while in progress or when the log was cut off.
    public var end: LogPosition?
    /// The latest BG turn reached; final once the game has ended.
    public var bgTurn: Int
}

/// The event-driven history layer over the entity store: which solo Battlegrounds
/// games happened, and when each started and ended.
///
/// Feed it every `EntityChange` with the store as it is after the change, and call
/// `refresh` at batch boundaries so projected fields stay current.
public struct BGGameHistory: Sendable {
    public private(set) var games: [BGGameRecord] = []
    /// Index into `games` of the store's current game, when that game is solo Battlegrounds.
    public private(set) var currentIndex: Int?

    public init() {}

    public var current: BGGameRecord? { currentIndex.map { games[$0] } }

    public mutating func observe(_ change: EntityChange, in store: EntityStore, at position: LogPosition) {
        switch change {
        case .gameCreated:
            currentIndex = nil
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
            }
        default:
            break
        }
    }

    public mutating func refresh(from store: EntityStore) {
        guard let index = currentIndex, let snapshot = BGSnapshot.project(store) else { return }
        var record = games[index]
        record.gameSeed = snapshot.gameSeed ?? record.gameSeed
        record.buildNumber = snapshot.buildNumber ?? record.buildNumber
        record.localPlayerID = snapshot.localPlayerID ?? record.localPlayerID
        record.localHeroCardID = snapshot.localHero?.cardID ?? record.localHeroCardID
        record.bgTurn = max(record.bgTurn, snapshot.bgTurn)
        games[index] = record
    }
}
