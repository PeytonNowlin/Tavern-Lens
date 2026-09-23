import BGIntel
import HSData

@_exported import struct BGIntel.BuildMatch
@_exported import enum BGIntel.ShopCardRole

/// The builds the local player is leaning into, the shop cards that fit them, and how to
/// play them.
public struct BuildsView: Codable, Hashable, Sendable {
    /// 0-2 builds, the strongest first.
    public var detected: [DetectedBuildView]
    /// Shop cards that are core or add-on cards of the detected builds.
    public var shopHighlights: [ShopHighlightView]
    /// The build data is the cached or bundled copy, not a fresh fetch.
    public var catalogIsStale: Bool

    public init(detected: [DetectedBuildView] = [], shopHighlights: [ShopHighlightView] = [], catalogIsStale: Bool = false) {
        self.detected = detected
        self.shopHighlights = shopHighlights
        self.catalogIsStale = catalogIsStale
    }

    private enum CodingKeys: String, CodingKey { case detected, shopHighlights, catalogIsStale }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        detected = try c.decodeIfPresent([DetectedBuildView].self, forKey: .detected) ?? []
        shopHighlights = try c.decodeIfPresent([ShopHighlightView].self, forKey: .shopHighlights) ?? []
        catalogIsStale = try c.decodeIfPresent(Bool.self, forKey: .catalogIsStale) ?? false
    }

    // Compact JSON: empty lists and the flag when false are left out.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !detected.isEmpty { try c.encode(detected, forKey: .detected) }
        if !shopHighlights.isEmpty { try c.encode(shopHighlights, forKey: .shopHighlights) }
        if catalogIsStale { try c.encode(catalogIsStale, forKey: .catalogIsStale) }
    }
}

/// One detected build, with its tips card.
public struct DetectedBuildView: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    /// Display names of its tribes (`Beast`); empty for a tribe-agnostic build.
    public var tribes: [String]
    /// Its core cards the player has, and the ones still missing.
    public var coreHave: [String]
    public var coreMissing: [String]
    /// Its add-ons the player has.
    public var addonsHave: [String]
    public var tips: BuildTipsView
    /// `firestone` or `overrides` (our file: a hypothesis, not stats-backed).
    public var source: BuildDefinition.Source

    public init(
        id: String, name: String, tribes: [String], coreHave: [String], coreMissing: [String], addonsHave: [String],
        tips: BuildTipsView, source: BuildDefinition.Source
    ) {
        self.id = id
        self.name = name
        self.tribes = tribes
        self.coreHave = coreHave
        self.coreMissing = coreMissing
        self.addonsHave = addonsHave
        self.tips = tips
        self.source = source
    }
}

/// A build's short tips card: key cards, when to commit, and what it needs.
public struct BuildTipsView: Codable, Hashable, Sendable {
    /// The core cards, the defining ones first.
    public var keyCards: [String]
    /// A few add-ons worth picking up.
    public var addons: [String]
    public var whenToCommit: String?
    public var tip: String?
    public var difficulty: String?
    public var powerLevel: String?
    /// Average placement over games that ended on it (all players), to 2 decimals.
    public var averagePlacement: Double?

    public init(
        keyCards: [String], addons: [String] = [], whenToCommit: String? = nil, tip: String? = nil,
        difficulty: String? = nil, powerLevel: String? = nil, averagePlacement: Double? = nil
    ) {
        self.keyCards = keyCards
        self.addons = addons
        self.whenToCommit = whenToCommit
        self.tip = tip
        self.difficulty = difficulty
        self.powerLevel = powerLevel
        self.averagePlacement = averagePlacement
    }
}

/// A shop card to highlight: which slot, and whether it's core or an add-on.
public struct ShopHighlightView: Codable, Hashable, Sendable {
    /// The card's place in `GameView.shop.cards` (0 = leftmost), which is its slot on screen.
    public var index: Int
    public var cardID: String
    public var role: ShopCardRole
    public var buildID: String

    public init(index: Int, cardID: String, role: ShopCardRole, buildID: String) {
        self.index = index
        self.cardID = cardID
        self.role = role
        self.buildID = buildID
    }
}

/// The build an opponent's last-seen board most looks like.
public struct LikelyBuildView: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    /// Their core and add-on cards of the build that were on the board.
    public var matchedCards: [String]

    public init(id: String, name: String, matchedCards: [String]) {
        self.id = id
        self.name = name
        self.matchedCards = matchedCards
    }
}

/// The current game's build detection, fed from the engine's published view states.
///
/// Detection runs at each publish on what the view shows (board, hand, trinkets, shop, the
/// lobby's tribes and Deity); a new game starts it over, a reconnect carries on.
struct BuildTracker: Sendable {
    private(set) var catalog: BuildCatalog?
    private var detector: BuildDetector?
    private var gameIndex: Int?

    init(catalog: BuildCatalog?) {
        use(catalog)
    }

    /// Sets (or replaces) the build catalog; detection starts over with it.
    mutating func use(_ catalog: BuildCatalog?) {
        self.catalog = catalog
        detector = catalog.map(BuildDetector.init)
    }

    /// Adds the builds to `game`: the detected builds and shop highlights, and each
    /// opponent's likely build on their last-seen board.
    mutating func apply(to game: inout GameView, gameIndex: Int?) {
        guard var detector, let catalog else { return }
        if gameIndex != self.gameIndex {
            detector.reset()
            self.gameIndex = gameIndex
        }
        let absent = Set((game.tribes?.tribes ?? []).filter { $0.confidence == .absent }.compactMap { HS.Race(name: $0.tribe) })
        let deity = game.mechanics?.deityDbfID
        var view = BuildsView(catalogIsStale: catalog.provenance.isStale)
        if game.phase != .heroPick, let player = game.player {
            let cards = player.board.map(\.cardID) + player.hand.map(\.cardID)
                + (player.mechanics?.trinkets.map(\.cardID) ?? [])
            let matches = detector.update(
                BuildInput(cardIDs: cards, bgTurn: game.bgTurn, absentTribes: absent, deityDbfID: deity)
            )
            view.detected = matches.map(DetectedBuildView.init)
            view.shopHighlights = ShopHighlighter.highlights(
                shop: game.shop.cards.map(\.cardID), builds: matches, catalog: catalog
            ).map { ShopHighlightView(index: $0.index, cardID: $0.cardID, role: $0.role, buildID: $0.buildID) }
        }
        game.builds = view
        for index in game.lobby.indices {
            guard let board = game.lobby[index].lastSeenBoard else { continue }
            let likely = detector.likelyBuild(cardIDs: board.cards.map(\.cardID), absentTribes: absent, deityDbfID: deity)
            game.lobby[index].lastSeenBoard?.likelyBuild = likely.map {
                LikelyBuildView(id: $0.build.id, name: $0.build.name, matchedCards: $0.core + $0.addons)
            }
        }
        self.detector = detector
    }
}

extension DetectedBuildView {
    init(_ match: BuildMatch) {
        let build = match.build
        self.init(
            id: build.id, name: build.name, tribes: build.tribes.map(TribeView.displayName),
            coreHave: match.core, coreMissing: match.missingCore, addonsHave: match.addons,
            tips: BuildTipsView(
                keyCards: build.core, addons: Array(build.addons.prefix(4)), whenToCommit: build.whenToCommit,
                tip: build.tip, difficulty: build.difficulty, powerLevel: build.powerLevel,
                averagePlacement: build.averagePlacement.map { ($0 * 100).rounded() / 100 }
            ),
            source: build.source
        )
    }
}
