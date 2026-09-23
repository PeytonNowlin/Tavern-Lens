import EntityStore
import HSData
import PowerParser

/// One entity of the current game as the debug window lists it: card and tag names
/// resolved, raw numbers kept where no name is known.
public struct EntityRow: Codable, Hashable, Sendable, Identifiable {
    public struct Tag: Codable, Hashable, Sendable {
        /// The tag's name, or its number when the pinned enums don't know it.
        public var tag: String
        /// The tag number, when known.
        public var number: Int?
        public var value: String

        public init(tag: String, number: Int?, value: String) {
            self.tag = tag
            self.number = number
            self.value = value
        }
    }

    public var id: Int
    public var cardID: String
    /// Nil without card data, for an unknown card, or for an entity with no card.
    public var cardName: String?
    public var tags: [Tag]
}

extension EntityRow {
    init(_ entity: Entity, cards: CardDB?) {
        id = entity.id
        cardID = entity.cardID
        cardName = entity.cardID.isEmpty ? nil : cards?.name(of: entity.cardID)
        tags = entity.tags
            .map { Tag(tag: $0.key.description, number: $0.key.number, value: $0.value.description) }
            .sorted { ($0.number ?? .max, $0.tag) < ($1.number ?? .max, $1.tag) }
    }
}
