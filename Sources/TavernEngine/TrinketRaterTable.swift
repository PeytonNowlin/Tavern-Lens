import Foundation

/// The board-fit model a trinket follows. Cards are bound to a model by card ID in
/// `TrinketRaterTable`, so a text rewording cannot silently drop a trinket back to "unrated".
enum TrinketEffect: Sendable {
    /// Buffs the board now and again after every discard.
    case sludgeCorrosion
    /// Repeats the board's end-of-turn effects.
    case endOfTurnRepeat
    /// "At the end of your turn, give your minions +A/+H"; the numbers are read from the card text.
    case endOfTurnBuff
    /// Becomes a copy of the next Greater Trinket bought.
    case souvenirStand
    /// Three random Tier 4 minions.
    case tierFourMinions
    /// A tailored Tier 4 minion with a Dark Gift.
    case darkGiftDiscover
    /// Two random Tavern spells each turn; only one of each pair can be played.
    case spellPairs
    /// Bigger Tavern spell buffs; needs spells to cast.
    case spellBuffs
}

/// Named weights behind the board-fit scores. They are judgement calls, not fitted values.
enum TrinketWeights {
    /// Greater Trinket stand-in used until the Souvenir Stand pays off; above this health it is worth investing.
    static let standInvestScore = 9.0, standRiskyScore = 2.0
    /// Flat scores for one-shot minion trinkets.
    static let tierFourMinionsScore = 9.0, darkGiftDiscoverScore = 8.0
    /// Each end-of-turn effect the repeat trinket doubles is worth this many points per turn of horizon.
    static let endOfTurnRepeatValue = 4.0
    /// Share of a per-turn board buff counted per turn of horizon.
    static let endOfTurnBuffShare = 0.5
    /// Spell buff points per spell supplied, per turn of horizon.
    static let spellBuffValue = 2.0
    /// Spell pairs supplied per turn of horizon.
    static let spellPairsPerTurn = 2.0
    /// A copied trinket (Souvenir Stand) counts for this much more.
    static let standCopyMultiplier = 2.0
    /// Gold cost penalty per gold.
    static let costPenalty = 1.5

    /// Turns the engine is expected to keep running, by hero health.
    static let criticalHP = 10, healthyHP = 20
    static let criticalHorizon = 1.0, wornHorizon = 2.0, healthyHorizon = 3.0

    /// Population prior: placements better than `priorNeutralPlacement` add up to `priorLimit` points.
    static let priorNeutralPlacement = 4.5, priorPerPlacement = 8.0, priorLimit = 8.0
    /// Score given to a trinket with only population data, before the prior and cost.
    static let baselineScore = 8.0

    /// Rating labels cut at these scores.
    static let strongFit = 16.0, goodFit = 6.0

    static func horizon(hp: Int) -> Double {
        hp <= criticalHP ? criticalHorizon : hp <= healthyHP ? wornHorizon : healthyHorizon
    }
}

enum TrinketRaterTable {
    static let souvenirStandID = "BG30_MagicItem_888"

    static let effects: [String: TrinketEffect] = [
        "BG36_MagicItem_430": .sludgeCorrosion,  // Sludge Portrait
        "BG32_MagicItem_367": .endOfTurnRepeat,  // Ghastly Sticker
        "BG36_MagicItem_302": .endOfTurnBuff,    // Gold Mallet
        "BG36_MagicItem_302t": .endOfTurnBuff,   // Gold Mallet, improved
        "BG36_MagicItem_414": .endOfTurnBuff,    // Weighted Gauntlet
        souvenirStandID: .souvenirStand,         // Souvenir Stand
        "BG32_MagicItem_858": .tierFourMinions,  // Explorer's Binoculars
        "BG36_MagicItem_206": .darkGiftDiscover, // Ominous Stone
        "BG36_MagicItem_852": .spellPairs,       // Willbreaker Sticker
        "BG36_MagicItem_371": .spellBuffs,       // Honeycomb Ring
    ]

    static let buffPattern = try? NSRegularExpression(pattern: "give your minions \\+([0-9]+)/\\+([0-9]+)")
    static let buffPrefix = "At the end of your turn, give your minions +"
}
