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
    /// The combat the advisor scores against: nil input means there's nothing to score against
    /// (no opponent seen yet). Against `standIn`'s side when there is one.
    public var preview: OddsPreviewRequest
    /// Recruit data and effect definitions captured with the request for deterministic planning.
    public var recruit: RecruitContext?
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
    /// This turn's gold income (`RESOURCES`), for the economy term's look ahead; nil while unknown
    /// (then the usual curve, turn + 2 up to 10, is assumed).
    public var income: Int?
    /// The most gold a turn can give (10 unless something raised it); nil while unknown.
    public var goldCap: Int?
    /// The other opponents with a last-seen board, for the lobby term (the next opponent is the
    /// preview's); nil when not gathered (a request from before the lobby term existed).
    public var lobby: [AdvisorLobbyOpponent]?
    /// The builds the player is leaning into (0-2, the strongest first), for the build term; nil
    /// without build data.
    public var builds: [AdvisorBuild]?
    /// The base card of every golden card in the request (`…_G` or `TB_BaconUps_*` → the normal
    /// card), when it isn't simply the ID without `_G`; for matching build cards and pairs.
    public var baseCardIDs: [String: String]?
    /// When the next opponent hasn't been fought yet, or their board is `staleBoardTurns` or more
    /// turns old: the opponent whose last-seen side the combat term fights in their place (the
    /// most recently seen one, fresher than theirs), with the next opponent's health and tier.
    /// `preview.input` is against it, and it isn't in `lobby`; the next opponent's old board is.
    /// Nil when the next opponent's own board is used.
    public var standIn: AdvisorLobbyOpponent?

    public static let boardLimit = 7
    public static let handLimit = 10
    /// What a minion costs when its `COST` isn't known.
    public static let defaultMinionCost = 3
    /// What selling a minion gives.
    public static let sellValue = 1

    public init(
        preview: OddsPreviewRequest, gold: Int, tier: Int, board: [AdvisorCard], hand: [AdvisorCard],
        shop: [AdvisorCard], levelCost: Int? = nil, rollCost: Int? = nil, canFreeze: Bool = false,
        shopFrozen: Bool = false, income: Int? = nil, goldCap: Int? = nil, lobby: [AdvisorLobbyOpponent]? = nil,
        builds: [AdvisorBuild]? = nil, baseCardIDs: [String: String]? = nil, standIn: AdvisorLobbyOpponent? = nil
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
        self.income = income
        self.goldCap = goldCap
        self.lobby = lobby
        self.builds = builds
        self.baseCardIDs = baseCardIDs
        self.standIn = standIn
    }

    /// One per game, BG turn and next opponent (the preview's); the state within it changes.
    public var id: String { preview.id }
    public var hasData: Bool { preview.hasData || recruit != nil }

    /// A card's base card (a golden's normal card), for build cards and pairs.
    public func baseCardID(_ cardID: String) -> String {
        if let base = baseCardIDs?[cardID] { return base }
        if cardID.hasSuffix("_G") { return String(cardID.dropLast(2)) }
        return cardID
    }

    /// A next opponent's board this many turns old is too weak a guess at theirs now (boards
    /// grow every turn): a fresher one stands in.
    public static let staleBoardTurns = 3

    /// The BG turn the next opponent's own board is from, when a stand-in replaced it because it
    /// was old; nil when they haven't been seen or there's no stand-in.
    public var replacedSeenTurn: Int? {
        guard standIn != nil else { return nil }
        return lobby?.first { $0.playerID == preview.opponentPlayerID }?.seenTurn
    }

    /// Who the combat term fights, for the reasons shown: "next opponent", or the stand-in's
    /// "last opponent" (fought last turn) or "turn N opponent".
    public var opponentLabel: String {
        guard let standIn else { return "next opponent" }
        return standIn.seenTurn == preview.bgTurn - 1 ? "last opponent" : "turn \(standIn.seenTurn) opponent"
    }

    /// The most recently seen of `lobby`, the combat term's opponent when the next one hasn't been
    /// seen (the closest to the boards the lobby has now); a combat-start side before a rebuilt
    /// one, then the lower PlayerID. Nil without a living one.
    public static func standIn(from lobby: [AdvisorLobbyOpponent]) -> AdvisorLobbyOpponent? {
        func key(_ o: AdvisorLobbyOpponent) -> (Int, Int, Int) { (o.seenTurn, o.source == .combatStart ? 1 : 0, -o.playerID) }
        return lobby.filter { $0.side.player.hpLeft > 0 }.max { key($0) < key($1) }
    }

    /// The local hero's health now; nil without data.
    public var health: Int? { preview.input?.playerBoard.player.hpLeft }

    /// The combat against one of the lobby's other opponents, with the local side of `input` (a
    /// candidate's board) and everything else of the next combat's.
    public func input(_ input: BattleInput, against opponent: AdvisorLobbyOpponent) -> BattleInput {
        var result = input
        result.opponentBoard = opponent.side
        return result
    }
}

/// One of the lobby's other opponents as the lobby term fights them: their last-seen side, with
/// health and tier as they are now.
public struct AdvisorLobbyOpponent: Codable, Hashable, Sendable {
    public var playerID: Int
    /// The BG turn their board was last seen (the last combat against them).
    public var seenTurn: Int
    public var source: OddsPreviewRequest.OpponentSource
    public var side: BattleBoard

    public init(playerID: Int, seenTurn: Int, source: OddsPreviewRequest.OpponentSource, side: BattleBoard) {
        self.playerID = playerID
        self.seenTurn = seenTurn
        self.source = source
        self.side = side
    }
}

/// A build the player is leaning into, as the build term counts progress toward it.
public struct AdvisorBuild: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    /// How much it counts: 1 for the first detected build, less for the second.
    public var share: Double
    /// Base card IDs.
    public var core: [String]
    public var addons: [String]
    /// The tavern tier of each core card, where known (levelling toward a missing one is progress).
    public var coreTiers: [String: Int]

    public init(id: String, name: String, share: Double, core: [String], addons: [String], coreTiers: [String: Int] = [:]) {
        self.id = id
        self.name = name
        self.share = share
        self.core = core
        self.addons = addons
        self.coreTiers = coreTiers
    }
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
            shopFrozen: snapshot.shop.isFrozen,
            income: local.gold.resources,
            goldCap: local.gold.cap
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
