import BGState
import EntityStore
import HSData
import PowerParser

/// Supplies the lobby's tribes for the simulator's `validTribes`, which the log doesn't carry.
///
/// The engine sends the tribe inference's lobby (`TribeResolver`, with the hero-pick banner
/// reading) when it has a pool; an injected provider overrides that, and without either
/// `SeenPoolMinionTribes` stands in.
public protocol LobbyTribesProvider: Sendable {
    /// The lobby's tribes at this moment, or nil while they aren't known (the simulator then
    /// allows every tribe, which only affects random summons).
    func lobbyTribes(store: EntityStore, snapshot: BGSnapshot) -> Set<HS.Race>?
}

/// The stopgap tribe source: the tribes of single-tribe pool minions seen so far this game
/// (mapping §7). Dual-tribe cards are ignored, since the log prints only one `CARDRACE` for
/// them; the card data says which cards they are, so without card data this knows nothing.
/// Only a complete set of five is returned.
public struct SeenPoolMinionTribes: LobbyTribesProvider {
    public let cards: CardDB?
    public var lobbySize = 5

    public init(cards: CardDB?) {
        self.cards = cards
    }

    public func lobbyTribes(store: EntityStore, snapshot: BGSnapshot) -> Set<HS.Race>? {
        guard let cards else { return nil }
        var tribes: Set<HS.Race> = []
        var seen: Set<String> = []
        for entity in store.entities.values
        where entity.int(Self.isBaconPoolMinion) == 1 && entity.name(.cardType) == "MINION" {
            guard seen.insert(entity.cardID).inserted, var card = cards[entity.cardID] else { continue }
            if let normal = card.battlegroundsNormalDbfId.flatMap(cards.card(dbfID:)) { card = normal }
            guard card.isBattlegroundsPoolMinion == true else { continue }
            let own = card.tribes.filter { $0 != .all }
            if own.count == 1 { tribes.insert(own[0]) }
        }
        return tribes.count == lobbySize ? tribes : nil
    }

    static let isBaconPoolMinion = GameTag(token: "IS_BACON_POOL_MINION")
}
