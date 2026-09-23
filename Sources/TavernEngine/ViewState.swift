import BGState
import HSData
import PowerParser

/// What the overlay and menu bar show at one moment. This is the engine's output
/// and what golden tests compare, so it holds only what a player would see.
public struct ViewState: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Hashable, Sendable {
        /// No solo Battlegrounds game (none yet, or another mode is being played).
        case noGame
        case inGame
        case gameOver
    }

    public var status: Status
    public var game: GameView?

    public static let noGame = ViewState(status: .noGame, game: nil)

    public init(status: Status, game: GameView?) {
        self.status = status
        self.game = game
    }
}

/// The solo Battlegrounds game on screen.
public struct GameView: Codable, Hashable, Sendable {
    public var gameType: String
    public var localPlayerID: Int?
    /// Card ID of the local hero; nil until the hero pick resolves.
    public var localHeroCardID: String?
    /// The local hero's name from the card data; nil without card data or before the hero pick.
    public var localHeroName: String?
    /// The Battlegrounds turn (0 before the first recruit phase).
    public var bgTurn: Int
    public var phase: BGPhase
    /// The local player's stats, board and hand; nil before the Player entities exist.
    public var player: PlayerView?
    /// Bob's shop; empty during combat.
    public var shop: ShopView

    public init(
        gameType: String, localPlayerID: Int?, localHeroCardID: String?, localHeroName: String? = nil, bgTurn: Int,
        phase: BGPhase = .heroPick, player: PlayerView? = nil, shop: ShopView = ShopView()
    ) {
        self.gameType = gameType
        self.localPlayerID = localPlayerID
        self.localHeroCardID = localHeroCardID
        self.localHeroName = localHeroName
        self.bgTurn = bgTurn
        self.phase = phase
        self.player = player
        self.shop = shop
    }
}

/// The local player.
public struct PlayerView: Codable, Hashable, Sendable {
    /// Nil until the hero pick resolves.
    public var hero: HeroStatsView?
    public var gold: GoldView
    /// Tavern tier.
    public var tier: Int?
    /// Minions in play, left to right.
    public var board: [CardView]
    /// Cards in hand, left to right.
    public var hand: [CardView]

    public init(hero: HeroStatsView?, gold: GoldView, tier: Int?, board: [CardView], hand: [CardView]) {
        self.hero = hero
        self.gold = gold
        self.tier = tier
        self.board = board
        self.hand = hand
    }
}

/// A hero's health and triples.
public struct HeroStatsView: Codable, Hashable, Sendable {
    /// Effective health: `health − damage + armor`.
    public var hp: Int
    public var health: Int
    public var damage: Int
    public var armor: Int
    public var triples: Int

    public init(hp: Int, health: Int, damage: Int, armor: Int, triples: Int) {
        self.hp = hp
        self.health = health
        self.damage = damage
        self.armor = armor
        self.triples = triples
    }
}

/// The local player's gold this turn.
public struct GoldView: Codable, Hashable, Sendable {
    /// Gold left to spend.
    public var available: Int
    /// This turn's gold before spending.
    public var thisTurn: Int
    public var used: Int
    /// Extra gold for this turn only.
    public var temporary: Int
    /// The most gold a turn can give; nil until the game sets it.
    public var cap: Int?

    public init(available: Int, thisTurn: Int, used: Int, temporary: Int, cap: Int?) {
        self.available = available
        self.thisTurn = thisTurn
        self.used = used
        self.temporary = temporary
        self.cap = cap
    }
}

/// Bob's shop.
public struct ShopView: Codable, Hashable, Sendable {
    /// Minions and tavern spells for sale, left to right.
    public var cards: [CardView]
    /// Every card is frozen.
    public var isFrozen: Bool

    public init(cards: [CardView] = [], isFrozen: Bool = false) {
        self.cards = cards
        self.isFrozen = isFrozen
    }
}

/// One card on a board, in a hand or in the shop. Order in the containing list is its position.
public struct CardView: Codable, Hashable, Sendable {
    public var cardID: String
    /// From the card data; nil without it or for an unknown card.
    public var name: String?
    public var kind: BGCardKind
    /// Attack and health left; nil for cards that aren't minions.
    public var attack: Int?
    public var health: Int?
    public var golden: Bool
    /// The card's tavern tier.
    public var tier: Int?
    public var keywords: [BGKeyword]

    public init(
        cardID: String, name: String? = nil, kind: BGCardKind, attack: Int? = nil, health: Int? = nil,
        golden: Bool = false, tier: Int? = nil, keywords: [BGKeyword] = []
    ) {
        self.cardID = cardID
        self.name = name
        self.kind = kind
        self.attack = attack
        self.health = health
        self.golden = golden
        self.tier = tier
        self.keywords = keywords
    }

    public var frozen: Bool { keywords.contains(.frozen) }

    // Compact JSON: `golden` and `keywords` are written only when set.
    private enum CodingKeys: String, CodingKey {
        case cardID, name, kind, attack, health, golden, tier, keywords
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cardID = try c.decode(String.self, forKey: .cardID)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        kind = try c.decode(BGCardKind.self, forKey: .kind)
        attack = try c.decodeIfPresent(Int.self, forKey: .attack)
        health = try c.decodeIfPresent(Int.self, forKey: .health)
        golden = try c.decodeIfPresent(Bool.self, forKey: .golden) ?? false
        tier = try c.decodeIfPresent(Int.self, forKey: .tier)
        keywords = try c.decodeIfPresent([BGKeyword].self, forKey: .keywords) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cardID, forKey: .cardID)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(attack, forKey: .attack)
        try c.encodeIfPresent(health, forKey: .health)
        if golden { try c.encode(golden, forKey: .golden) }
        try c.encodeIfPresent(tier, forKey: .tier)
        if !keywords.isEmpty { try c.encode(keywords, forKey: .keywords) }
    }
}

/// A view state and the log position where it took effect.
public struct TimelineEntry: Codable, Hashable, Sendable {
    public var position: LogPosition
    public var state: ViewState

    public init(position: LogPosition, state: ViewState) {
        self.position = position
        self.state = state
    }
}

// MARK: - From the snapshot

extension GameView {
    init(_ snapshot: BGSnapshot, cards: CardDB?) {
        self.init(
            gameType: snapshot.gameType,
            localPlayerID: snapshot.localPlayerID,
            localHeroCardID: snapshot.localHero?.cardID,
            localHeroName: snapshot.localHero.flatMap { cards?.name(of: $0.cardID) },
            bgTurn: snapshot.bgTurn,
            phase: snapshot.phase,
            player: snapshot.local.map { PlayerView($0, cards: cards) },
            shop: ShopView(
                cards: snapshot.shop.cards.map { CardView($0, cards: cards) },
                isFrozen: snapshot.shop.isFrozen
            )
        )
    }
}

extension PlayerView {
    init(_ local: BGLocalPlayer, cards: CardDB?) {
        self.init(
            hero: local.hero.map(HeroStatsView.init),
            gold: GoldView(
                available: local.gold.available, thisTurn: local.gold.resources, used: local.gold.used,
                temporary: local.gold.temporary, cap: local.gold.cap
            ),
            tier: local.tier,
            board: local.board.map { CardView($0, cards: cards) },
            hand: local.hand.map { CardView($0, cards: cards) }
        )
    }
}

extension HeroStatsView {
    init(_ hero: BGHeroState) {
        self.init(hp: hero.hp, health: hero.health, damage: hero.damage, armor: hero.armor, triples: hero.triples)
    }
}

extension CardView {
    init(_ card: BGCard, cards: CardDB?) {
        let isMinion = card.kind == .minion
        self.init(
            cardID: card.cardID,
            name: card.cardID.isEmpty ? nil : cards?.name(of: card.cardID),
            kind: card.kind,
            attack: isMinion ? card.attack : nil,
            health: isMinion ? card.health : nil,
            golden: card.isGolden,
            tier: card.tier,
            keywords: card.keywords
        )
    }
}
