/// A Hearthstone game tag, kept numeric.
///
/// The client prints a tag's name when it has one (`tag=ZONE`) and its number
/// otherwise (`tag=2022`). Names are resolved to numbers through `GameTag.names`.
/// A name the table doesn't know is kept as `.unresolved(name)` so that parsing
/// never fails on a new tag; the full generated table (from HearthstoneJSON
/// `enums.json`) replaces the built-in subset below with the card-data ticket.
public enum GameTag: Hashable, Sendable {
    case id(Int)
    case unresolved(String)

    /// Parses the token after `tag=`: a number or a name.
    public init(token: Substring) {
        if let number = Int(token) {
            self = .id(number)
        } else if let number = GameTag.names[String(token)] {
            self = .id(number)
        } else {
            self = .unresolved(String(token))
        }
    }

    public var number: Int? {
        if case .id(let n) = self { return n }
        return nil
    }
}

extension GameTag: CustomStringConvertible {
    public var description: String {
        switch self {
        case .id(let n): GameTag.nameByNumber[n] ?? String(n)
        case .unresolved(let name): name
        }
    }
}

// Tags the engine reads, with numbers from HearthstoneJSON enums.json (build 251952).
public extension GameTag {
    static let premium = GameTag.id(12)
    static let playState = GameTag.id(17)
    static let step = GameTag.id(19)
    static let turn = GameTag.id(20)
    static let currentPlayer = GameTag.id(23)
    static let resourcesUsed = GameTag.id(25)
    static let resources = GameTag.id(26)
    static let heroEntity = GameTag.id(27)
    static let playerID = GameTag.id(30)
    static let damage = GameTag.id(44)
    static let health = GameTag.id(45)
    static let atk = GameTag.id(47)
    static let zone = GameTag.id(49)
    static let controller = GameTag.id(50)
    static let entityID = GameTag.id(53)
    static let maxResources = GameTag.id(176)
    static let cardType = GameTag.id(202)
    static let state = GameTag.id(204)
    static let frozen = GameTag.id(260)
    static let zonePosition = GameTag.id(263)
    static let armor = GameTag.id(292)
    static let tempResources = GameTag.id(295)
    static let boardVisualState = GameTag.id(1347)
    static let baconDummyPlayer = GameTag.id(1349)
    static let nextOpponentPlayerID = GameTag.id(1360)
    static let playerLeaderboardPlace = GameTag.id(1373)
    static let playerTechLevel = GameTag.id(1377)
    static let techLevel = GameTag.id(1440)
    static let playerTriples = GameTag.id(1447)
    static let copiedFromEntityID = GameTag.id(1565)
    static let gameSeed = GameTag.id(2042)
    static let baconCurrentCombatPlayerID = GameTag.id(2989)
    static let baconDuoTeamID = GameTag.id(3095)
}

extension GameTag {
    /// Built-in name table: the tags above. Replaced by the generated table later.
    static let names: [String: Int] = [
        "PREMIUM": 12, "PLAYSTATE": 17, "STEP": 19, "TURN": 20, "CURRENT_PLAYER": 23,
        "RESOURCES_USED": 25, "RESOURCES": 26, "HERO_ENTITY": 27, "PLAYER_ID": 30,
        "DAMAGE": 44, "HEALTH": 45, "ATK": 47, "ZONE": 49, "CONTROLLER": 50, "ENTITY_ID": 53,
        "MAXRESOURCES": 176, "CARDTYPE": 202, "STATE": 204, "FROZEN": 260, "ZONE_POSITION": 263,
        "ARMOR": 292, "TEMP_RESOURCES": 295, "BOARD_VISUAL_STATE": 1347, "BACON_DUMMY_PLAYER": 1349,
        "NEXT_OPPONENT_PLAYER_ID": 1360, "PLAYER_LEADERBOARD_PLACE": 1373, "PLAYER_TECH_LEVEL": 1377,
        "TECH_LEVEL": 1440, "PLAYER_TRIPLES": 1447, "COPIED_FROM_ENTITY_ID": 1565, "GAME_SEED": 2042,
        "BACON_CURRENT_COMBAT_PLAYER_ID": 2989, "BACON_DUO_TEAM_ID": 3095,
    ]

    static let nameByNumber: [Int: String] = Dictionary(
        names.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first }
    )
}

/// A tag value: a number, or an enum name such as `PLAY`, `MINION` or `COMPLETE`.
public enum TagValue: Hashable, Sendable {
    case int(Int)
    case name(String)

    public init(token: Substring) {
        if let number = Int(token) {
            self = .int(number)
        } else {
            self = .name(String(token))
        }
    }

    public var intValue: Int? {
        if case .int(let n) = self { return n }
        return nil
    }

    public var nameValue: String? {
        if case .name(let s) = self { return s }
        return nil
    }
}

extension TagValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .int(let n): String(n)
        case .name(let s): s
        }
    }
}
