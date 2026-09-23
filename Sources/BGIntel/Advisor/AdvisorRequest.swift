import BGState
import EntityStore
import HSData
import PowerParser

/// One recruit-phase state as the advisor reads it: the odds preview's combat (the local side as it
/// is now against the next opponent's last-seen side), plus what the player can do about it: gold,
/// the shop, the hand and the tavern buttons.
///
/// Every candidate action builds its hypothetical board from this alone, so candidate generation
/// and ranking are pure functions of the request (and of the simulated scores).
public struct AdvisorRequest: Codable, Hashable, Sendable {
    /// The combat the advisor scores against: nil input means the next opponent hasn't been seen.
    public var preview: OddsPreviewRequest
    /// Gold left to spend now.
    public var gold: Int
    public var tier: Int
    /// The local minions in play, left to right (the order the overlay highlights them in).
    public var board: [AdvisorCard]
    /// Cards in hand, left to right.
    public var hand: [AdvisorCard]
    /// Bob's minions and tavern spells for sale, left to right.
    public var shop: [AdvisorCard]
    /// The tavern upgrade's price now; nil at the top tier (no upgrade button) or while unknown.
    public var levelCost: Int?
    /// The refresh's price now; nil while unknown.
    public var rollCost: Int?
    /// The freeze button is there.
    public var canFreeze: Bool
    /// Every shop card is frozen already.
    public var shopFrozen: Bool

    public static let boardLimit = 7
    public static let handLimit = 10
    /// What a minion costs when its `COST` isn't known.
    public static let defaultMinionCost = 3
    /// What selling a minion gives.
    public static let sellValue = 1

    public init(
        preview: OddsPreviewRequest, gold: Int, tier: Int, board: [AdvisorCard], hand: [AdvisorCard],
        shop: [AdvisorCard], levelCost: Int? = nil, rollCost: Int? = nil, canFreeze: Bool = false,
        shopFrozen: Bool = false
    ) {
        self.preview = preview
        self.gold = gold
        self.tier = tier
        self.board = board
        self.hand = hand
        self.shop = shop
        self.levelCost = levelCost
        self.rollCost = rollCost
        self.canFreeze = canFreeze
        self.shopFrozen = shopFrozen
    }

    /// One per game, BG turn and next opponent (the preview's); the state within it changes.
    public var id: String { preview.id }
    public var hasData: Bool { preview.hasData }
}

/// A card the advisor can act on: in play, in hand or in the shop.
public struct AdvisorCard: Codable, Hashable, Sendable {
    public var cardID: String
    public var kind: BGCardKind
    /// Its `COST` (a shop card's price); nil when not set.
    public var cost: Int?
    public var golden: Bool
    /// The card's tavern tier.
    public var tier: Int?
    /// The card as the simulator reads a minion (stats with every buff, keywords, enchantments).
    public var entity: BattleEntity

    public init(cardID: String, kind: BGCardKind, cost: Int? = nil, golden: Bool = false, tier: Int? = nil, entity: BattleEntity) {
        self.cardID = cardID
        self.kind = kind
        self.cost = cost
        self.golden = golden
        self.tier = tier
        self.entity = entity
    }

    public var isMinion: Bool { kind == .minion }
}

extension BattleInputBuilder {
    /// The advisor's view of the recruit phase now: `preview` (from `preview(store:snapshot:…)`)
    /// plus the gold, board, hand, shop and tavern buttons. Nil outside recruit or without a local player.
    public static func advisorRequest(store: EntityStore, snapshot: BGSnapshot, preview: OddsPreviewRequest) -> AdvisorRequest? {
        guard snapshot.phase == .recruit, let local = snapshot.local, let slot = store.localPlayer else { return nil }
        func cards(_ list: [BGCard]) -> [AdvisorCard] {
            let entities = battleEntities(ids: list.map(\.entityID), in: store)
            guard entities.count == list.count else { return [] }
            return zip(list, entities).map { card, entity in
                AdvisorCard(
                    cardID: card.cardID, kind: card.kind, cost: store[card.entityID]?.int(AdvisorTag.cost),
                    golden: card.isGolden, tier: card.tier, entity: entity
                )
            }
        }
        // The tavern buttons are the local player's GAME_MODE_BUTTON entities in PLAY; older copies
        // linger in SETASIDE. The newest of each kind is the one on screen.
        let buttons = store.entities(controller: slot.playerID, zone: "PLAY")
            .filter { $0.name(.cardType) == "GAME_MODE_BUTTON" }
            .sorted { $0.id < $1.id }
        func cost(where matches: (String) -> Bool) -> Int?? {
            guard let button = buttons.last(where: { matches($0.cardID) }) else { return nil }
            return .some(button.int(AdvisorTag.cost))
        }
        let level = cost { $0.hasPrefix(AdvisorCardID.levelButtonPrefix) }
        let roll = cost { $0.contains(AdvisorCardID.rollButtonMarker) }
        let freeze = cost { $0 == AdvisorCardID.freezeButton }
        return AdvisorRequest(
            preview: preview,
            gold: local.gold.available,
            tier: local.tier ?? 1,
            board: cards(local.board),
            hand: cards(local.hand),
            shop: cards(snapshot.shop.cards),
            levelCost: level.flatMap { $0 },
            rollCost: roll.flatMap { $0 },
            canFreeze: freeze != nil,
            shopFrozen: snapshot.shop.isFrozen
        )
    }
}

enum AdvisorTag {
    static let cost = GameTag.id(48)
}

enum AdvisorCardID {
    /// `TB_BaconShopTechUp02_Button` … `TB_BaconShopTechUp07_Button`.
    static let levelButtonPrefix = "TB_BaconShopTechUp"
    /// `TB_BaconShop_8p_Reroll_Button`.
    static let rollButtonMarker = "Reroll_Button"
    static let freezeButton = "TB_BaconShopLockAll_Button"
}
