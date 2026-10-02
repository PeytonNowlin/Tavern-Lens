/// An action reference deliberately contains no display name or account identifier.
public struct ActionEntity: Codable, Hashable, Sendable {
    public var entityID: Int
    public var cardID: String
    public init(entityID: Int, cardID: String = "") {
        self.entityID = entityID; self.cardID = cardID
    }
}

public struct PowerOptionTarget: Codable, Hashable, Sendable {
    public var index: Int
    public var entity: ActionEntity
    public var error: String?
    public var errorParam: String?
    public init(index: Int, entity: ActionEntity, error: String? = nil, errorParam: String? = nil) {
        self.index = index; self.entity = entity; self.error = error; self.errorParam = errorParam
    }
}

public struct PowerSubOption: Codable, Hashable, Sendable {
    public var index: Int
    public var entity: ActionEntity
    public var error: String?
    public var errorParam: String?
    public var targets: [PowerOptionTarget]
    public init(index: Int, entity: ActionEntity, error: String? = nil, errorParam: String? = nil,
                targets: [PowerOptionTarget] = []) {
        self.index = index; self.entity = entity; self.error = error
        self.errorParam = errorParam; self.targets = targets
    }
}

public struct PowerOption: Codable, Hashable, Sendable {
    public var index: Int
    public var type: String
    public var mainEntity: ActionEntity?
    public var error: String?
    public var errorParam: String?
    public var targets: [PowerOptionTarget]
    public var subOptions: [PowerSubOption]
    public init(index: Int, type: String, mainEntity: ActionEntity? = nil, error: String? = nil,
                errorParam: String? = nil, targets: [PowerOptionTarget] = [], subOptions: [PowerSubOption] = []) {
        self.index = index; self.type = type; self.mainEntity = mainEntity; self.error = error
        self.errorParam = errorParam; self.targets = targets; self.subOptions = subOptions
    }
}

/// One offered group, including rejected targets. The log does not provide every possible UI action.
public struct PowerOptions: Codable, Hashable, Sendable {
    public var id: Int
    public var timestamp: String
    public var position: LogPosition?
    public var options: [PowerOption]
    /// False when a row is malformed or a safety bound prevents retaining it.
    public var isComplete: Bool
    public init(id: Int, timestamp: String, position: LogPosition? = nil,
                options: [PowerOption] = [], isComplete: Bool = true) {
        self.id = id; self.timestamp = timestamp; self.position = position
        self.options = options; self.isComplete = isComplete
    }
}

/// A client selection; optionsID is the preceding offered group, not a field in SendOption.
public struct SentOption: Codable, Hashable, Sendable {
    public var timestamp: String
    public var position: LogPosition?
    public var optionsID: Int?
    public var selectedOption: Int
    public var selectedSubOption: Int
    public var selectedTarget: Int
    public var selectedPosition: Int
    public init(timestamp: String, position: LogPosition? = nil, optionsID: Int? = nil,
                selectedOption: Int, selectedSubOption: Int, selectedTarget: Int, selectedPosition: Int) {
        self.timestamp = timestamp; self.position = position; self.optionsID = optionsID
        self.selectedOption = selectedOption; self.selectedSubOption = selectedSubOption
        self.selectedTarget = selectedTarget; self.selectedPosition = selectedPosition
    }
}

/// A complete outgoing choice block, emitted before the next log packet's effects.
public struct SentChoices: Codable, Hashable, Sendable {
    public var timestamp: String
    public var position: LogPosition?
    public var id: Int
    public var choiceType: String
    public var chosen: [ActionEntity]
    public var isComplete: Bool
    public init(timestamp: String, position: LogPosition? = nil, id: Int, choiceType: String,
                chosen: [ActionEntity] = [], isComplete: Bool = true) {
        self.timestamp = timestamp; self.position = position; self.id = id
        self.choiceType = choiceType; self.chosen = chosen; self.isComplete = isComplete
    }
}
