/// Something the player could do this recruit phase. The advisor only suggests; it never acts.
///
/// Indices are positions in the request's lists (0 = leftmost): `shop` in `AdvisorRequest.shop`,
/// `hand` in `hand`, `board` in `board`, and `place` the board position the minion ends up at.
public enum AdvisorAction: Codable, Hashable, Sendable {
    /// The board as it is: the baseline every other action is compared with. Never suggested.
    case activate(board: Int, cardID: String, cost: Int, discard: Int?, discardedCardID: String?)
    case keep
    case darkDiscovery(cost: Int, minTier: Int, maxTier: Int)
    case heroPower(cardID: String, cost: Int, target: Int?, targetCardID: String?)
    /// Buy a shop minion and play it at `place`.
    case buy(shop: Int, cardID: String, place: Int)
    /// Play a minion from hand at `place`.
    case play(hand: Int, cardID: String, place: Int)
    case sell(board: Int, cardID: String)
    /// The board is full: sell `sell` (for gold and room), then buy a shop minion and play it in the sold one's place.
    case swap(shop: Int, cardID: String, sell: Int, soldCardID: String)
    /// Buy (from the shop) or play (from hand) a tavern spell, on `target` when it takes one.
    /// `option` is the Choose One option (0 otherwise).
    case cast(from: SpellSource, index: Int, cardID: String, option: Int, target: Int?, targetCardID: String?)
    /// Drag a minion to another position.
    case move(board: Int, cardID: String, to: Int)
    case level(cost: Int, toTier: Int)
    case roll(cost: Int)
    case freeze

    public enum SpellSource: String, Codable, Hashable, Sendable {
        case shop, hand
    }

    /// Candidates in the same group are one suggestion with different details (where a bought
    /// minion goes, which minion a spell targets); only a group's best one is ever suggested.
    public var group: String {
        switch self {
        case .activate(let board, _, _, _, _): "activate:b\(board)"
        case .darkDiscovery: "darkDiscovery"
        case .heroPower: "heroPower"
        case .keep: "keep"
        case .buy(let shop, _, _): "buy:s\(shop)"
        case .play(let hand, _, _): "play:h\(hand)"
        case .sell(let board, _): "sell:b\(board)"
        case .swap(let shop, _, _, _): "swap:s\(shop)"
        case .cast(let from, let index, _, _, _, _): "cast:\(from.rawValue)\(index)"
        case .move(let board, _, _): "move:b\(board)"
        case .level: "level"
        case .roll: "roll"
        case .freeze: "freeze"
        }
    }

    /// Unique among one request's candidates, and stable across runs.
    public var id: String {
        switch self {
        case .activate(_, _, _, let hand, _): "\(group)-h\(hand ?? -1)"
        case .heroPower(_, _, let target, _): "heroPower-b\(target ?? -1)"
        case .keep, .level, .roll, .freeze, .sell, .darkDiscovery: group
        case .buy(_, _, let place), .play(_, _, let place): "\(group)@\(place)"
        case .swap(_, _, let sell, _): "\(group)-b\(sell)"
        case .cast(_, _, _, let option, let target, _): "\(group)o\(option)" + (target.map { "-b\($0)" } ?? "")
        case .move(_, _, let to): "\(group)@\(to)"
        }
    }

    /// Whether it changes the board the next combat is fought with (level, roll and freeze don't).
    public var changesBoard: Bool {
        switch self {
        case .keep, .level, .roll, .freeze, .darkDiscovery: false
        default: true
        }
    }

    /// The overlay elements the action is about, most important first: highlighted in place
    /// with the suggestion's rank.
    public var targets: [AdvisorTarget] {
        switch self {
        case .activate(let board, _, _, let hand, _): [.init(.board, board)] + (hand.map { [.init(.hand, $0)] } ?? [])
        case .heroPower(_, _, let target, _): target.map { [.init(.board, $0)] } ?? []
        case .darkDiscovery: [] // No calibrated screen target for this button yet.
        case .keep: []
        case .buy(let shop, _, _): [.init(.shop, shop)]
        case .play(let hand, _, _): [.init(.hand, hand)]
        case .sell(let board, _): [.init(.board, board)]
        case .swap(let shop, _, let sell, _): [.init(.shop, shop), .init(.board, sell)]
        case .cast(let from, let index, _, _, let target, _):
            [.init(from == .shop ? .shop : .hand, index)] + (target.map { [.init(.board, $0)] } ?? [])
        case .move(let board, _, _): [.init(.board, board)]
        case .level: [.init(.levelButton)]
        case .roll: [.init(.rollButton)]
        case .freeze: [.init(.freezeButton)]
        }
    }

    /// A short imperative title, with card names from `name` (card ID → name; the ID when unknown).
    public func title(name: (String) -> String = { $0 }) -> String {
        switch self {
        case .activate(_, let card, _, _, let discarded): discarded.map { "Activate \(name(card)): discard \(name($0))" } ?? "Activate \(name(card))"
        case .heroPower(let card, _, _, let target): target.map { "\(name(card)) on \(name($0))" } ?? "Use \(name(card))"
        case .darkDiscovery(let cost, _, _): "Use Dark Discovery (\(cost) Gold)"
        case .keep: "Keep your board"
        case .buy(_, let card, _): "Buy \(name(card))"
        case .play(_, let card, _): "Play \(name(card))"
        case .sell(_, let card): "Sell \(name(card))"
        case .swap(_, let card, _, let sold): "Sell \(name(sold)), buy \(name(card))"
        case .cast(_, _, let card, _, _, let target):
            target.map { "\(name(card)) on \(name($0))" } ?? "Cast \(name(card))"
        case .move(_, let card, let to): "Move \(name(card)) to slot \(to + 1)"
        case .level(_, let tier): "Level to tier \(tier)"
        case .roll: "Refresh the tavern"
        case .freeze: "Freeze the tavern"
        }
    }
}

/// An overlay element a suggestion highlights: a shop card, a board minion, a card in hand or a
/// tavern button. Indices are 0-based from the left.
public struct AdvisorTarget: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case shop, board, hand, levelButton, rollButton, freezeButton
    }

    public var kind: Kind
    public var index: Int?

    public init(_ kind: Kind, _ index: Int? = nil) {
        self.kind = kind
        self.index = index
    }
}
