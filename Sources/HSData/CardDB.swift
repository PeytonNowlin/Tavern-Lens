import Foundation

/// One card from HearthstoneJSON `cards.json`, with the fields Tavern Lens reads.
///
/// Enum-like fields stay as the names HearthstoneJSON prints (`MINION`, `QUILBOAR`) so a
/// name newer than the pinned enums is kept; the typed accessors map them to `HS` enums.
public struct Card: Codable, Hashable, Sendable {
    /// The card ID the log prints (`BG20_100`).
    public var id: String
    public var dbfId: Int
    public var name: String
    public var type: String?
    public var set: String?
    public var text: String?
    public var cardClass: String?
    public var rarity: String?
    public var cost: Int?
    public var attack: Int?
    public var health: Int?
    public var armor: Int?
    /// Tavern tier.
    public var techLevel: Int?
    public var races: [String]?
    public var mechanics: [String]?
    public var referencedTags: [String]?
    public var spellSchool: String?
    public var isBattlegroundsPoolMinion: Bool?
    public var isBattlegroundsPoolSpell: Bool?
    public var isBattlegroundsDuosExclusive: Bool?
    public var battlegroundsHero: Bool?
    /// The golden version of a normal Battlegrounds minion.
    public var battlegroundsPremiumDbfId: Int?
    /// The normal version of a golden Battlegrounds minion.
    public var battlegroundsNormalDbfId: Int?
    public var heroPowerDbfId: Int?
    public var battlegroundsBuddyDbfId: Int?

    public init(id: String, dbfId: Int, name: String) {
        self.id = id
        self.dbfId = dbfId
        self.name = name
    }

    public var cardType: HS.CardType? { type.flatMap { HS.CardType(name: $0) } }

    /// Tribes; `races` is absent for untyped cards.
    public var tribes: [HS.Race] { (races ?? []).compactMap { HS.Race(name: $0) } }
}

/// The card data of one Hearthstone build, looked up by card ID or dbfId.
public struct CardDB: Sendable {
    /// The build the data is for, when known.
    public let build: Int?
    public let cards: [Card]
    private let byID: [String: Int]
    private let byDbfID: [Int: Int]

    public init(build: Int?, cards: [Card]) {
        self.build = build
        self.cards = cards
        byID = Dictionary(cards.indices.map { (cards[$0].id, $0) }, uniquingKeysWith: { first, _ in first })
        byDbfID = Dictionary(cards.indices.map { (cards[$0].dbfId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Decodes HearthstoneJSON `cards.json` (one locale: a top-level array of cards).
    public init(build: Int?, json: Data) throws {
        try self.init(build: build, cards: JSONDecoder().decode([Card].self, from: json))
    }

    public var count: Int { cards.count }

    public subscript(id: String) -> Card? { byID[id].map { cards[$0] } }

    public func card(dbfID: Int) -> Card? { byDbfID[dbfID].map { cards[$0] } }

    /// The card's name, or nil for an unknown or empty card ID.
    public func name(of cardID: String) -> String? { self[cardID]?.name }
}
