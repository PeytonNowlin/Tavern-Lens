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

/// One option of an entity choice: the entity and the card it showed when the choice was printed.
public struct ChoiceOption: Hashable, Sendable {
    public var entityID: Int
    /// Empty when the log printed none (a hidden card).
    public var cardID: String

    public init(entityID: Int, cardID: String) {
        self.entityID = entityID
        self.cardID = cardID
    }
}

/// A choice the server offered the local player (`GameState.DebugPrintEntityChoices`):
/// the Battlegrounds hero pick is a `MULLIGAN` choice, discovers and trinket offers are `GENERAL`.
public struct EntityChoice: Hashable, Sendable {
    /// The choice's `id=`, which `DebugPrintEntitiesChosen` repeats.
    public var id: Int
    /// `MULLIGAN`, `GENERAL`, …
    public var choiceType: String
    /// The `TaskList=` the choice is shown with, if printed.
    public var taskList: Int?
    /// What offered the choice (`GameEntity` for the hero pick, the discover's card otherwise).
    public var source: EntityRef?
    /// The source's card, when printed in bracket form.
    public var sourceCardID: String?
    public var options: [ChoiceOption]

    public init(
        id: Int, choiceType: String, taskList: Int? = nil, source: EntityRef? = nil, sourceCardID: String? = nil,
        options: [ChoiceOption] = []
    ) {
        self.id = id
        self.choiceType = choiceType
        self.taskList = taskList
        self.source = source
        self.sourceCardID = sourceCardID
        self.options = options
    }
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

    /// `GameState.DebugPrintEntityChoices`: a choice offered to the local player. It comes
    /// from the early `GameState` stream, before the task list that shows it.
    case entityChoices(EntityChoice)
    /// `GameState.DebugPrintEntitiesChosen`: what the player picked for choice `choiceID`.
    case entitiesChosen(choiceID: Int, chosen: [ChoiceOption])

    /// `PowerProcessor.EndCurrentTaskList`: a batch finished, state is settled.
    case taskListEnd
}
