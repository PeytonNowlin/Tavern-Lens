import Foundation
import HSData

/// Firestone's hero tier letter, from how far a hero's average placement is from the field's.
public enum HeroTier: String, Codable, CaseIterable, Hashable, Sendable {
    case S, A, B, C, D, E
}

/// How the lobby's tribes adjusted a hero's average placement.
public enum HeroTribeAdjustment: String, Codable, Hashable, Sendable {
    /// Not adjusted: the lobby's tribes aren't known at all (no minion pool).
    case none
    /// Weighted by how likely each tribe is to be in the lobby (it isn't resolved yet).
    case estimated
    /// The lobby's tribes are known: Firestone's sum over them.
    case exact
}

/// The lobby's tribes as the hero-pick stats weigh them: each tribe's chance of being in the
/// lobby, leaving out the tribes forced into every lobby this patch (their "impact" is the
/// patch's, not the tribe's; research §3).
public struct HeroPickTribes: Hashable, Sendable {
    /// P(in the lobby) by `Race` number, forced tribes left out.
    public var weights: [Int: Double]
    public var adjustment: HeroTribeAdjustment
    /// Every tribe of the lobby, forced ones included, once it's known (`exact`).
    public var lobby: Set<Int>

    public init(weights: [Int: Double], adjustment: HeroTribeAdjustment, lobby: Set<Int> = []) {
        self.weights = weights
        self.adjustment = adjustment
        self.lobby = lobby
    }

    /// From the tribe resolver: exact once every tribe is confirmed or ruled out, otherwise
    /// each tribe weighted by its probability, which is the expected value of Firestone's sum.
    public init(_ estimate: TribeEstimate) {
        var weights: [Int: Double] = [:]
        for tribe in estimate.tribes where !tribe.isForced {
            let weight = estimate.isResolved ? (tribe.confidence == .confirmed ? 1 : 0) : tribe.probability
            if weight > 0 { weights[tribe.tribe.rawValue] = weight }
        }
        self.init(
            weights: weights, adjustment: estimate.isResolved ? .exact : .estimated,
            lobby: Set((estimate.lobby ?? []).map(\.rawValue))
        )
    }

    /// No tribe information: no adjustment.
    public static let unknown = HeroPickTribes(weights: [:], adjustment: .none)
}

/// One hero's pick stats, as the hero-pick plate shows them.
public struct HeroPickStat: Hashable, Sendable {
    /// The base hero the stats are for (skins are folded into it).
    public var heroCardID: String
    public var window: HeroStatsWindow
    /// Games behind the numbers.
    public var dataPoints: Int
    /// Firestone's `averagePosition` for the hero.
    public var baseAveragePlacement: Double
    /// The lobby's tribes' summed impact (negative is better).
    public var tribeModifier: Double
    /// `baseAveragePlacement + tribeModifier`: the number shown.
    public var averagePlacement: Double
    public var tier: HeroTier
    public var top4Percent: Double
    public var winPercent: Double
    /// Percent of games in each place, 1st to 8th.
    public var placements: [Double]
    public var pickRate: Double?
    public var conservativeEstimate: Double?
}

/// Firestone's hero-selection numbers (docs/research/hero-pick-stats.md §3), with the tribe
/// modifier leaving out forced tribes:
///
/// 1. Each hero's row comes from the newest window where it has enough games (past three days,
///    then past seven, then last patch).
/// 2. A tribe row counts only if it has more than 1/20 of the hero's games and its "without"
///    side has more than 1/20 of its own games.
/// 3. The shown average is `averagePosition + Σ impactAveragePosition` over the lobby's tribes
///    (each weighted by its probability until the lobby is resolved).
/// 4. Heroes with fewer than 30 games are left out, and the others' shown averages give the
///    tiers: S below μ−3σ, A below μ−1.5σ, B below μ, C below μ+σ, D below μ+2σ, E beyond.
public struct HeroPickEvaluator: Sendable {
    public static let minimumGamesForTier = 30

    public let stats: HeroStatsSet
    public let tribes: HeroPickTribes
    /// Mean and standard deviation of every eligible hero's shown average.
    public let mean: Double
    public let standardDeviation: Double

    /// - Parameter heroRules: once the lobby is known, heroes that couldn't be offered in it
    ///   (Firestone's `needTypesInLobby`) are left out of the tier cut-offs.
    public init(
        stats: HeroStatsSet, tribes: HeroPickTribes = .unknown, heroRules: ((String) -> HeroTribeRule?)? = nil
    ) {
        self.stats = stats
        self.tribes = tribes
        var shown: [Double] = []
        for hero in stats.heroCardIDs {
            guard let (stat, _) = stats.stat(for: hero), stat.dataPoints >= Self.minimumGamesForTier else { continue }
            if tribes.adjustment == .exact, let rule = heroRules?(hero), !Self.offerable(rule, in: tribes) { continue }
            shown.append(stat.averagePosition + Self.modifier(stat, tribes))
        }
        let mean = shown.isEmpty ? 0 : shown.reduce(0, +) / Double(shown.count)
        let variance = shown.isEmpty ? 0 : shown.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(shown.count)
        self.mean = mean
        standardDeviation = variance.squareRoot()
    }

    /// The stats for a base hero card ID; nil when no window has it.
    public func evaluate(_ heroCardID: String) -> HeroPickStat? {
        guard let (stat, window) = stats.stat(for: heroCardID) else { return nil }
        let modifier = Self.modifier(stat, tribes)
        let shown = stat.averagePosition + modifier
        return HeroPickStat(
            heroCardID: heroCardID, window: window, dataPoints: stat.dataPoints,
            baseAveragePlacement: stat.averagePosition, tribeModifier: modifier, averagePlacement: shown,
            tier: tier(of: shown), top4Percent: stat.top4Percent, winPercent: stat.winPercent,
            placements: stat.placements, pickRate: stat.pickRate, conservativeEstimate: stat.conservativePositionEstimate
        )
    }

    public func tier(of average: Double) -> HeroTier {
        let (m, s) = (mean, standardDeviation)
        if average < m - 3 * s { return .S }
        if average < m - 1.5 * s { return .A }
        if average < m { return .B }
        if average < m + s { return .C }
        if average < m + 2 * s { return .D }
        return .E
    }

    /// Σ impact over the tribe rows that pass Firestone's noise filter, weighted by the tribe's
    /// chance of being in the lobby.
    static func modifier(_ stat: FirestoneHeroStat, _ tribes: HeroPickTribes) -> Double {
        guard !tribes.weights.isEmpty else { return 0 }
        var sum = 0.0
        for row in stat.tribeStats {
            guard let weight = tribes.weights[row.tribe],
                  Double(row.dataPoints) > Double(stat.dataPoints) / 20,
                  Double(row.dataPointsOnMissingTribe) > Double(row.dataPoints) / 20
            else { continue }
            sum += weight * row.impactAveragePosition
        }
        return sum
    }

    /// The hero can be offered in the (known) lobby: it has one of the tribes it needs, when
    /// it needs any, and none it's banned with. Forced tribes are in every lobby.
    private static func offerable(_ rule: HeroTribeRule, in tribes: HeroPickTribes) -> Bool {
        let lobby = tribes.lobby
        let needs = rule.needsAny.map(\.rawValue)
        if !needs.isEmpty, !needs.contains(where: lobby.contains) { return false }
        return !rule.bannedWithAny.map(\.rawValue).contains(where: lobby.contains)
    }
}

/// Maps an offered hero to the base hero Firestone keys its stats by (a port of Firestone's
/// `normalizeHeroCardId`, research §6): the skin's `BACON_SKIN_PARENT_ID`, else the card
/// data's skin parent, else the `_SKIN_` naming convention, then two special cases.
public enum HeroCardNormalizer {
    public static func baseCardID(_ cardID: String, skinParentDbfID: Int? = nil, cards: CardDB? = nil) -> String {
        var base = cardID
        if let parent = skinParentDbfID, let card = cards?.card(dbfID: parent) {
            base = card.id
        } else if let parent = cards?[cardID]?.battlegroundsSkinParentId, let card = cards?.card(dbfID: parent) {
            base = card.id
        } else if let range = cardID.range(of: "_SKIN_") {
            base = String(cardID[..<range.lowerBound])
        }
        switch base {
        case "TB_BaconShop_HERO_59t": return "TB_BaconShop_HERO_59"
        // Queen Azshara's Naga-token hero.
        case "BG22_HERO_007t": return "BG22_HERO_007"
        default: return base
        }
    }
}
