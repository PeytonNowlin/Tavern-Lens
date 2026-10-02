/// Versioned card definitions select shared stat primitives. A changed definition stays
/// unsupported rather than inheriting a similarly worded effect from another card.
enum RecruitArcaneAbsorption: RecruitCardEffect {
    static let id = "BG35_911"
    static let text = "Give a friendly Elemental half the stats of the highest-Health minion in the Tavern."
    static let cardIDs: Set<String> = [id]
    static let since = 11

    static func supported(_ context: RecruitContext) -> Bool {
        context.definitions[id]?.type == "BATTLEGROUND_SPELL" && context.text(id) == text
    }

    private static func stats(_ state: RecruitState) -> (Int, Int)? {
        let minions = state.shop.filter(\.isMinion)
        guard let health = minions.map({ $0.entity.health }).max(), health > 0 else { return nil }
        let highest = minions.filter { $0.entity.health == health }
        guard let source = highest.first, source.entity.attack >= 0,
              highest.allSatisfy({ $0.entity.attack == source.entity.attack && $0.entity.maxHealth == health }) else { return nil }
        // The captured 218/219 source granted 109/110. Identical-stat ties have the
        // same result; a tie with different Attack requires a new observation.
        return (source.entity.attack / 2 + source.entity.attack % 2, health / 2 + health % 2)
    }

    static func spellEffect(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> RecruitEffects.Effect? {
        if RecruitFortify.hasTavernSpellModifier(state, context: context) {
            return .unsupported("Tavern spell stat modifier is unmodelled")
        }
        guard !card.isMinion, supported(context), let stats = stats(state) else {
            return .unsupported("Arcane Absorption needs a known highest-Health source")
        }
        return .buff(stats.0, stats.1, all: false)
    }

    static func spellTargetAllowed(_ card: AdvisorCard, target: Int?, state: RecruitState, context: RecruitContext) -> Bool? {
        guard supported(context), stats(state) != nil,
              let recipient = state.board.first(where: { $0.entity.entityId == target }),
              let tribes = context.definitions[recipient.cardID]?.races else { return false }
        return tribes.contains("ELEMENTAL") || tribes.contains("ALL")
    }
}

enum RecruitFortify: RecruitCardEffect {
    static let cardIDs: Set<String> = ["BG28_503"]
    static let since = 11

    /// Shared with Arcane Absorption: a board aura changes what a Tavern spell gives.
    static func hasTavernSpellModifier(_ state: RecruitState, context: RecruitContext) -> Bool {
        state.board.contains(where: { context.text($0.cardID).lowercased().contains("tavern spells give") })
    }

    static func spellEffect(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> RecruitEffects.Effect? {
        if hasTavernSpellModifier(state, context: context) {
            return .unsupported("Tavern spell stat modifier is unmodelled")
        }
        guard !card.isMinion, context.definitions[card.cardID]?.type == "BATTLEGROUND_SPELL",
              context.text(card.cardID) == "Give a minion +3 Health and Taunt." else {
            return .unsupported("Changed Fortify definition")
        }
        return .buffTaunt(0, 3)
    }
}

enum RecruitLeylineSurfacer: RecruitCardEffect {
    static let cardIDs: Set<String> = ["BG35_881", "BG35_881_G"]
    static let since = 11
    static let generated = [RecruitArcaneAbsorption.id]

    static func battlecry(_ card: AdvisorCard, context: RecruitContext) -> RecruitEffects.Effect? {
        let count = card.cardID == "BG35_881_G" ? 2 : 1
        let text = count == 2 ? "Battlecry and Deathrattle: Get 2 Arcane Absorptions."
            : "Battlecry and Deathrattle: Get an Arcane Absorption."
        guard card.isMinion, context.definitions[card.cardID]?.type == "MINION",
              context.text(card.cardID) == text, RecruitArcaneAbsorption.supported(context) else {
            return .unsupported("Leyline Surfacer needs its exact Arcane Absorption reward")
        }
        return .token(RecruitArcaneAbsorption.id, count, toHand: true)
    }
}
