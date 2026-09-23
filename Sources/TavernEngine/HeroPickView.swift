import BGIntel
import BGState
import Foundation
import HSData

@_exported import enum BGIntel.HeroTier
@_exported import enum BGIntel.HeroTribeAdjustment

/// The hero pick as the overlay shows it: each offered hero, left to right, with its stats.
public struct HeroPickView: Codable, Hashable, Sendable {
    public var offers: [HeroOfferView]
    /// The hero picked; nil while the player is still choosing (the plates show until then).
    public var chosenCardID: String?
    /// Firestone's MMR bucket (100 is all players).
    public var mmrPercentile: Int
    /// How the lobby's tribes adjusted the averages.
    public var tribeAdjustment: HeroTribeAdjustment
    /// When Firestone last rebuilt the oldest stats file shown (ISO 8601); nil without stats.
    public var statsUpdatedAt: String?
    /// The stats shown are more than 24 hours old at the game's time, or their age isn't known
    /// (a stats file without its date): show a stale badge.
    public var isStale: Bool

    public init(
        offers: [HeroOfferView], chosenCardID: String? = nil, mmrPercentile: Int = 100,
        tribeAdjustment: HeroTribeAdjustment = .none, statsUpdatedAt: String? = nil, isStale: Bool = false
    ) {
        self.offers = offers
        self.chosenCardID = chosenCardID
        self.mmrPercentile = mmrPercentile
        self.tribeAdjustment = tribeAdjustment
        self.statsUpdatedAt = statsUpdatedAt
        self.isStale = isStale
    }
}

/// One offered hero.
public struct HeroOfferView: Codable, Hashable, Sendable {
    /// The offered card, possibly a skin.
    public var cardID: String
    /// The base hero the stats are for.
    public var baseCardID: String
    /// From the card data; nil without it.
    public var name: String?
    /// Not pickable without the Tavern Pass.
    public var isLocked: Bool
    /// Nil when Firestone has no stats for the hero ("no data").
    public var stats: HeroPickStatsView?

    public init(cardID: String, baseCardID: String, name: String? = nil, isLocked: Bool = false, stats: HeroPickStatsView? = nil) {
        self.cardID = cardID
        self.baseCardID = baseCardID
        self.name = name
        self.isLocked = isLocked
        self.stats = stats
    }

    private enum CodingKeys: String, CodingKey {
        case cardID, baseCardID, name, isLocked, stats
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cardID = try c.decode(String.self, forKey: .cardID)
        baseCardID = try c.decode(String.self, forKey: .baseCardID)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        stats = try c.decodeIfPresent(HeroPickStatsView.self, forKey: .stats)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cardID, forKey: .cardID)
        try c.encode(baseCardID, forKey: .baseCardID)
        try c.encodeIfPresent(name, forKey: .name)
        if isLocked { try c.encode(isLocked, forKey: .isLocked) }
        try c.encodeIfPresent(stats, forKey: .stats)
    }
}

/// A hero's pick stats, rounded as shown.
public struct HeroPickStatsView: Codable, Hashable, Sendable {
    /// Average placement adjusted for the lobby's tribes, to 2 decimals.
    public var averagePlacement: Double
    /// Firestone's unadjusted average, to 2 decimals.
    public var baseAveragePlacement: Double
    /// The tribes' adjustment, to 2 decimals (negative is better).
    public var tribeModifier: Double
    /// Nil with fewer than 30 games behind the numbers: show "low data" instead of a letter.
    public var tier: HeroTier?
    /// Percent of games in the top 4, to 1 decimal.
    public var top4Percent: Double
    /// Percent of games won, to 1 decimal.
    public var winPercent: Double
    /// Percent of games in each place, 1st to 8th, to 1 decimal: the hover chart.
    public var placements: [Double]
    /// Games behind the numbers.
    public var dataPoints: Int
    /// The window the numbers come from (`past-three`, `past-seven` or `last-patch`).
    public var window: HeroStatsWindow

    public init(
        averagePlacement: Double, baseAveragePlacement: Double, tribeModifier: Double, tier: HeroTier?,
        top4Percent: Double, winPercent: Double, placements: [Double], dataPoints: Int, window: HeroStatsWindow
    ) {
        self.averagePlacement = averagePlacement
        self.baseAveragePlacement = baseAveragePlacement
        self.tribeModifier = tribeModifier
        self.tier = tier
        self.top4Percent = top4Percent
        self.winPercent = winPercent
        self.placements = placements
        self.dataPoints = dataPoints
        self.window = window
    }

    /// Too few games for a tier letter.
    public var isLowData: Bool { tier == nil }

    init(_ stat: HeroPickStat) {
        self.init(
            averagePlacement: Self.round(stat.averagePlacement, 2), baseAveragePlacement: Self.round(stat.baseAveragePlacement, 2),
            tribeModifier: Self.round(stat.tribeModifier, 2), tier: stat.tier, top4Percent: Self.round(stat.top4Percent, 1),
            winPercent: Self.round(stat.winPercent, 1), placements: stat.placements.map { Self.round($0, 1) },
            dataPoints: stat.dataPoints, window: stat.window
        )
    }

    private static func round(_ value: Double, _ places: Int) -> Double {
        let scale = pow(10, Double(places))
        let rounded = (value * scale).rounded() / scale
        return rounded == 0 ? 0 : rounded
    }
}

/// The hero-pick data the engine joins the offer with: Firestone's stats, and the card data
/// that maps skins to their base hero and names the heroes (the live engine may run without
/// card data of its own).
public struct HeroPickData: Sendable {
    public var stats: HeroStatsSet
    public var cards: CardDB?

    public init(stats: HeroStatsSet, cards: CardDB? = nil) {
        self.stats = stats
        self.cards = cards
    }
}

extension HeroPickView {
    /// Joins the hero pick with the stats. `now` is the game's time, for the stale badge.
    init(
        _ pick: BGHeroPick, data: HeroPickData, cards: CardDB?, tribes: TribeEstimate?, heroRules: ((String) -> HeroTribeRule?)?,
        now: Date?
    ) {
        let cards = data.cards ?? cards
        let tribeWeights = tribes.map(HeroPickTribes.init) ?? .unknown
        let evaluator = HeroPickEvaluator(stats: data.stats, tribes: tribeWeights, heroRules: heroRules)
        var windowsShown: Set<HeroStatsWindow> = []
        let offers = pick.offers.map { offer in
            let base = HeroCardNormalizer.baseCardID(offer.cardID, skinParentDbfID: offer.skinParentDbfID, cards: cards)
            let stat = evaluator.evaluate(base)
            if let stat { windowsShown.insert(stat.window) }
            return HeroOfferView(
                cardID: offer.cardID, baseCardID: base, name: cards?.name(of: offer.cardID) ?? cards?.name(of: base),
                isLocked: offer.isLocked, stats: stat.map(HeroPickStatsView.init)
            )
        }
        let dates = windowsShown.map(data.stats.lastUpdate(of:))
        let oldest = dates.compactMap { $0 }.min()
        // A window shown without its date is of unknown age: stale, whatever the time.
        let undated = dates.contains { $0 == nil }
        self.init(
            offers: offers, chosenCardID: pick.chosen?.cardID, mmrPercentile: data.stats.mmrPercentile,
            tribeAdjustment: tribeWeights.adjustment, statsUpdatedAt: oldest.map { $0.formatted(.iso8601) },
            isStale: undated || now.map { HeroStatsSet.isStale(updatedAt: oldest, now: $0) } == true
        )
    }
}
