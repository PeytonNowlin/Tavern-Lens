/// Trinkets whose recruit effect is already reflected in the observed client state, or whose
/// combat effect the pinned simulator owns. Exact definitions from the recorded games: a
/// changed text is unsupported rather than inheriting a similar effect.

enum RecruitOrnateClock: RecruitCardEffect {
    static let cardIDs: Set<String> = ["BG32_MagicItem_271"]
    static let since = AdvisorPolicy.Feature.greaterTrinketGold.introduced

    // Acquisition already granted gold and changed the trinket schedule in the
    // observed client state. It has no remaining recruit or combat projection event.
    static func trinketSupported(_ id: String, context: RecruitContext) -> Bool? {
        context.definitions[id]?.type == "BATTLEGROUND_TRINKET"
            && context.text(id) == "Gain 2 Gold. Buy your Greater Trinket next turn instead of Turn 9."
    }
}

enum RecruitDeathlyPhylactery: RecruitCardEffect {
    static let cardIDs: Set<String> = ["BG30_MagicItem_700"]
    static let since = AdvisorPolicy.Feature.observedTrinketState.introduced

    // The simulator consumes tags[32], not scriptDataNum1. Older recordings lack
    // that observation; never assume their first Deathrattle is still available.
    static func trinketSupported(_ id: String, context: RecruitContext) -> Bool? {
        context.text(id) == "Discover a Deathrattle minion. Your first Deathrattle each combat triggers an extra time."
            && context.input.playerBoard.player.trinkets.filter { $0.cardId == id }.allSatisfy {
                $0.tags?["32"] == 0 || $0.tags?["32"] == 1
            }
    }
}

enum RecruitManipulatorPortrait: RecruitCardEffect {
    static let cardIDs: Set<String> = ["BG30_MagicItem_876"]
    static let since = AdvisorPolicy.Feature.observedTrinketState.introduced

    // Its one-time reward is already observed in hand. This does not model the
    // separate Faceless Manipulator copy Battlecry or grant another copy.
    static func trinketSupported(_ id: String, context: RecruitContext) -> Bool? {
        context.text(id) == "Get a Faceless Manipulator."
    }
}

enum RecruitPocketCyclone: RecruitCardEffect {
    static let cardIDs: Set<String> = ["BG35_MagicItem_850", "BG35_MagicItem_850t"]
    static let since = AdvisorPolicy.Feature.easterlyWindsTrinkets.introduced

    // Past casts are reflected in observed shop stats. The next cast is next turn;
    // refreshes and repeated Tavern consumes retain their unknown-shop boundaries.
    static func trinketSupported(_ id: String, context: RecruitContext) -> Bool? {
        switch id {
        case "BG35_MagicItem_850": return context.text(id) == "Cast Easterly Winds. At the start of each turn, cast it again."
        default: return context.text(id) == "Cast Easterly Winds four times. At the start of each turn, cast it twice more."
        }
    }
}

enum RecruitFaerieDragonScale: RecruitCardEffect {
    static let cardIDs: Set<String> = ["BG32_MagicItem_363"]
    static let since = AdvisorPolicy.Feature.recordedEffects.introduced

    // faerie-dragon-scale.js owns shield grants and the remaining-use counter.
    static func trinketSupported(_ id: String, context: RecruitContext) -> Bool? {
        context.text(id) == "Whenever a friendly Dragon attacks, give it Divine Shield. (3 times per combat.)"
    }
}

enum RecruitBeetleBand: RecruitCardEffect {
    static let cardIDs: Set<String> = ["BG32_MagicItem_860t"]
    static let since = AdvisorPolicy.Feature.recordedEffects.introduced

    // beetle-band.js owns avenge, summon count, Taunt and the global Beetle buffs.
    static func trinketSupported(_ id: String, context: RecruitContext) -> Bool? {
        context.text(id) == "Avenge (7): Summon two 2/2 Beetles. Give them Taunt."
    }
}

enum RecruitRockinMusicBox: RecruitCardEffect {
    static let cardIDs: Set<String> = ["BG30_MagicItem_430"]
    static let since = AdvisorPolicy.Feature.recordedEffects.introduced

    // This turn's random reward is already observed in hand. The next arrives after
    // combat; never invent a card or resolve another reward in this projection.
    static func trinketSupported(_ id: String, context: RecruitContext) -> Bool? {
        context.text(id) == "Get a random Battlecry minion. At the start of each turn, get another."
    }
}

enum RecruitGoldMallet: RecruitCardEffect {
    static let cardIDs: Set<String> = ["BG36_MagicItem_302", "BG36_MagicItem_302t"]
    static let since = 0

    // The end-of-turn buff itself is resolved by the generic end-of-turn projection.
    static func trinketSupported(_ id: String, context: RecruitContext) -> Bool? {
        context.text(id).hasPrefix("At the end of your turn, give your minions +") ? true : nil
    }
}
