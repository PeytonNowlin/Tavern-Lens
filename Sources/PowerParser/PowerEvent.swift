/// How a log line names an entity.
///
/// Brackets (`[entityName=… id=N zone=… zonePos=… cardId=… player=…]`) are reduced
/// to their `id`: the other fields describe the entity *before* the line applies
/// and are stale. Player names are left for the entity store to bind, because only
/// it knows which Player entity is local.
public enum EntityRef: Hashable, Sendable {
    case gameEntity
    case id(Int)
    case playerName(String)
}

/// A tag written under an entity header (`tag=X value=Y`).
public struct TagAssignment: Hashable, Sendable {
    public var tag: GameTag
    public var value: TagValue

    public init(tag: GameTag, value: TagValue) {
        self.tag = tag
        self.value = value
    }
}

/// Game metadata from `GameState.DebugPrintGame`.
public enum GameMetadataField: Hashable, Sendable {
    case buildNumber(Int)
    /// A `GameType` enum name such as `GT_BATTLEGROUNDS`.
    case gameType(String)
    case formatType(String)
    case scenarioID(Int)
    case playerName(playerID: Int, name: String)
    case other(key: String, value: String)
}

/// A typed event from the power log.
///
/// State events come only from the synced `PowerTaskList` stream. The early
/// `GameState` stream contributes metadata and the announcement of a new game.
public enum PowerEvent: Hashable, Sendable {
    /// `GameState` printed `CREATE_GAME`: metadata that follows belongs to the next game.
    case newGameAnnounced
    case gameMetadata(GameMetadataField)

    /// `PowerTaskList` `CREATE_GAME`. The store resets here.
    case createGame
    case gameEntity(id: Int, tags: [TagAssignment])
    case player(entityID: Int, playerID: Int, accountHi: UInt64, accountLo: UInt64, tags: [TagAssignment])
    case fullEntity(EntityRef, cardID: String, tags: [TagAssignment])
    case showEntity(EntityRef, cardID: String, tags: [TagAssignment])
    case changeEntity(EntityRef, cardID: String, tags: [TagAssignment])
    case hideEntity(EntityRef)
    case tagChange(EntityRef, TagAssignment)
    case blockStart(type: String, entity: EntityRef?)
    case blockEnd

    /// `PowerProcessor.EndCurrentTaskList`: a batch finished, state is settled.
    case taskListEnd
}
