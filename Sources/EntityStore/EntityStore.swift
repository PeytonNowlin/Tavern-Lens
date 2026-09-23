import PowerParser

/// One game entity and its current tags.
public struct Entity: Hashable, Sendable {
    public let id: Int
    public var cardID: String
    public var tags: [GameTag: TagValue]

    public init(id: Int, cardID: String = "", tags: [GameTag: TagValue] = [:]) {
        self.id = id
        self.cardID = cardID
        self.tags = tags
    }

    public subscript(tag: GameTag) -> TagValue? { tags[tag] }

    /// A numeric tag, treating a missing tag as absent (callers choose the default).
    public func int(_ tag: GameTag) -> Int? { tags[tag]?.intValue }

    /// An enum-valued tag such as `ZONE` or `CARDTYPE`.
    public func name(_ tag: GameTag) -> String? { tags[tag]?.nameValue }
}

/// A Player entity from `CREATE_GAME`.
public struct PlayerSlot: Hashable, Sendable {
    public let entityID: Int
    public let playerID: Int
    /// A real account has a non-zero `GameAccountId`; the Battlegrounds bartender slot is `[hi=0 lo=0]`.
    public let hasAccount: Bool
}

/// Game metadata from `GameState.DebugPrintGame`.
public struct GameMetadata: Hashable, Sendable {
    public var buildNumber: Int?
    public var gameType: String?
    public var formatType: String?
    public var scenarioID: Int?
    public var playerNames: [Int: String] = [:]

    public init() {}

    mutating func apply(_ field: GameMetadataField) {
        switch field {
        case .buildNumber(let n): buildNumber = n
        case .gameType(let t): gameType = t
        case .formatType(let t): formatType = t
        case .scenarioID(let n): scenarioID = n
        case .playerName(let pid, let name): playerNames[pid] = name
        case .other: break
        }
    }
}

/// What a reduced event changed, for event-driven layers above the store.
public enum EntityChange: Hashable, Sendable {
    case gameCreated
    case entityCreated(id: Int)
    case tagChanged(entityID: Int, tag: GameTag, old: TagValue?, new: TagValue)
}

/// Counts of references the store could not bind.
public struct StoreDiagnostics: Hashable, Sendable, Codable {
    public var unboundPlayerNames = 0
    public var eventsBeforeGame = 0
    public var implicitEntities = 0

    public init() {}
}

/// A generic, deterministic reducer of power events into entities, tags, zones and controllers.
///
/// `CREATE_GAME` resets it. Metadata printed by `GameState` just before that is kept.
/// It knows nothing about Battlegrounds beyond the two Player entities.
///
/// A game is identified by the game entity's `GAME_SEED`. A reconnect resends the whole
/// game under a new `CREATE_GAME` with the same seed, and may leave out the
/// `DebugPrintGame` metadata; the store then keeps that game's earlier metadata.
public struct EntityStore: Sendable {
    public private(set) var entities: [Int: Entity] = [:]
    public private(set) var gameEntityID: Int?
    public private(set) var players: [PlayerSlot] = []
    /// Metadata for the current game.
    public private(set) var metadata = GameMetadata()
    public private(set) var diagnostics = StoreDiagnostics()
    /// Number of `CREATE_GAME`s seen.
    public private(set) var gamesCreated = 0

    private var announcedMetadata = GameMetadata()
    /// Metadata of the games seen (or remembered), by `GAME_SEED`, for reconnects.
    private var metadataBySeed: [Int: GameMetadata] = [:]
    private var announcedGameStarted = false
    /// Entity IDs by `(CONTROLLER, ZONE)`, kept in step with the tags so zone queries don't scan every entity.
    private var zoneIndex: [ZoneKey: Set<Int>] = [:]

    private struct ZoneKey: Hashable {
        var controller: Int?
        var zone: String?

        init(_ entity: Entity) {
            controller = entity.int(.controller)
            zone = entity.name(.zone)
        }

        init(controller: Int, zone: String) {
            self.controller = controller
            self.zone = zone
        }
    }

    public init() {}

    // MARK: - Queries

    public var gameEntity: Entity? { gameEntityID.flatMap { entities[$0] } }

    /// The local player: the Player entity with a real account.
    public var localPlayer: PlayerSlot? { players.first(where: \.hasAccount) }

    /// The other Player entity (in Battlegrounds, the bartender slot).
    public var otherPlayer: PlayerSlot? {
        let local = localPlayer
        return players.first(where: { $0 != local })
    }

    public subscript(id: Int) -> Entity? { entities[id] }

    /// Remembers a game that may be resumed in this log, such as one from the previous
    /// session's log when the client restarted mid-game: should its `CREATE_GAME` come
    /// without metadata, this metadata is used.
    public mutating func rememberGame(seed: Int, metadata: GameMetadata) {
        metadataBySeed[seed] = metadata
    }

    /// The entities with this `CONTROLLER` (a PlayerID) in this `ZONE` (`PLAY`, `HAND`, …), in no particular order.
    public func entities(controller: Int, zone: String) -> [Entity] {
        guard let ids = zoneIndex[ZoneKey(controller: controller, zone: zone)] else { return [] }
        return ids.compactMap { entities[$0] }
    }

    // MARK: - Reducer

    public mutating func apply(_ event: PowerEvent, changes: (EntityChange) -> Void = { _ in }) {
        switch event {
        case .newGameAnnounced:
            announcedMetadata = GameMetadata()
            announcedGameStarted = false
        case .gameMetadata(let field):
            announcedMetadata.apply(field)
            if announcedGameStarted { metadata.apply(field) }
        case .createGame:
            entities = [:]
            zoneIndex = [:]
            gameEntityID = nil
            players = []
            metadata = announcedMetadata
            announcedGameStarted = true
            gamesCreated += 1
            changes(.gameCreated)
        case .gameEntity(let id, let tags):
            guard started() else { return }
            gameEntityID = id
            if let seed = tags.last(where: { $0.tag == .gameSeed })?.value.intValue {
                if metadata.gameType == nil, let known = metadataBySeed[seed] {
                    metadata = known
                } else if metadata.gameType != nil {
                    metadataBySeed[seed] = metadata
                }
            }
            create(id: id, cardID: "", tags: tags, changes: changes)
        case .player(let eid, let pid, let hi, let lo, let tags):
            guard started() else { return }
            players.removeAll { $0.entityID == eid }
            players.append(PlayerSlot(entityID: eid, playerID: pid, hasAccount: hi != 0 || lo != 0))
            create(id: eid, cardID: "", tags: tags, changes: changes)
        case .fullEntity(let ref, let cardID, let tags):
            guard started(), let id = resolve(ref) else { return }
            create(id: id, cardID: cardID, tags: tags, changes: changes)
        case .showEntity(let ref, let cardID, let tags), .changeEntity(let ref, let cardID, let tags):
            guard started(), let id = resolve(ref) else { return }
            touch(id)
            entities[id]?.cardID = cardID
            for assignment in tags { set(id, assignment, changes: changes) }
        case .tagChange(let ref, let assignment):
            guard started(), let id = resolve(ref) else { return }
            touch(id)
            set(id, assignment, changes: changes)
        case .hideEntity:
            // The entity went out of view; a real ZONE change always follows.
            break
        case .blockStart, .blockEnd, .taskListEnd:
            break
        }
    }

    private mutating func started() -> Bool {
        if gamesCreated == 0 {
            diagnostics.eventsBeforeGame += 1
            return false
        }
        return true
    }

    private mutating func create(id: Int, cardID: String, tags: [TagAssignment], changes: (EntityChange) -> Void) {
        var entity = entities[id] ?? Entity(id: id)
        let oldKey = entities[id].map(ZoneKey.init)
        entity.cardID = cardID
        for assignment in tags { entity.tags[assignment.tag] = assignment.value }
        entities[id] = entity
        reindex(id, from: oldKey, to: ZoneKey(entity))
        changes(.entityCreated(id: id))
    }

    /// Makes sure `id` exists; a reference to an unseen id creates it implicitly.
    private mutating func touch(_ id: Int) {
        guard entities[id] == nil else { return }
        diagnostics.implicitEntities += 1
        let entity = Entity(id: id)
        entities[id] = entity
        reindex(id, from: nil, to: ZoneKey(entity))
    }

    private mutating func reindex(_ id: Int, from old: ZoneKey?, to new: ZoneKey) {
        guard old != new else { return }
        if let old { zoneIndex[old]?.remove(id) }
        zoneIndex[new, default: []].insert(id)
    }

    private mutating func set(_ id: Int, _ assignment: TagAssignment, changes: (EntityChange) -> Void) {
        let movesZone = assignment.tag == .zone || assignment.tag == .controller
        let oldKey = movesZone ? entities[id].map(ZoneKey.init) : nil
        let old = entities[id, default: Entity(id: id)].tags.updateValue(assignment.value, forKey: assignment.tag)
        if movesZone, let entity = entities[id] {
            reindex(id, from: oldKey, to: ZoneKey(entity))
        }
        if old != assignment.value {
            changes(.tagChanged(entityID: id, tag: assignment.tag, old: old, new: assignment.value))
        }
    }

    private mutating func resolve(_ ref: EntityRef) -> Int? {
        switch ref {
        case .gameEntity:
            return gameEntityID
        case .id(let id):
            return id
        case .playerName(let name):
            // The local BattleTag is constant. Every other name is the other Player entity,
            // whose printed name changes (placeholder, bartender skin, current opponent).
            if let local = localPlayer, metadata.playerNames[local.playerID] == name {
                return local.entityID
            }
            if let other = otherPlayer {
                return other.entityID
            }
            diagnostics.unboundPlayerNames += 1
            return nil
        }
    }
}
