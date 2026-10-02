/// Versioned card definitions select shared stat primitives. A changed definition stays
/// unsupported rather than inheriting a similarly worded effect from another card.
enum RecruitPolicy11Spells {
    static let absorptionID = "BG35_911"
    static let absorptionText = "Give a friendly Elemental half the stats of the highest-Health minion in the Tavern."

    static func supportsAbsorption(_ context: RecruitContext) -> Bool {
        context.definitions[absorptionID]?.type == "BATTLEGROUND_SPELL"
            && context.text(absorptionID) == absorptionText
    }

    private static func absorptionStats(_ state: RecruitState) -> (Int, Int)? {
        let minions = state.shop.filter(\.isMinion)
        guard let health = minions.map({ $0.entity.health }).max(), health > 0 else { return nil }
        let highest = minions.filter { $0.entity.health == health }
        guard let source = highest.first, source.entity.attack >= 0,
              highest.allSatisfy({ $0.entity.attack == source.entity.attack && $0.entity.maxHealth == health }) else { return nil }
        // The captured 218/219 source granted 109/110. Identical-stat ties have the
        // same result; a tie with different Attack requires a new observation.
        return (source.entity.attack / 2 + source.entity.attack % 2, health / 2 + health % 2)
    }

    static func effect(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> RecruitEffects.Effect? {
        guard (context.evaluationVersion ?? 0) >= 11 else { return nil }
        if card.cardID == "BG28_503" || card.cardID == absorptionID,
           state.board.contains(where: { context.text($0.cardID).lowercased().contains("tavern spells give") }) {
            return .unsupported("Tavern spell stat modifier is unmodelled")
        }
        switch card.cardID {
        case "BG28_503":
            guard !card.isMinion, context.definitions[card.cardID]?.type == "BATTLEGROUND_SPELL",
                  context.text(card.cardID) == "Give a minion +3 Health and Taunt." else {
                return .unsupported("Changed Fortify definition")
            }
            return .buffTaunt(0, 3)
        case absorptionID:
            guard !card.isMinion, supportsAbsorption(context), let stats = absorptionStats(state) else {
                return .unsupported("Arcane Absorption needs a known highest-Health source")
            }
            return .buff(stats.0, stats.1, all: false)
        default: return nil
        }
    }

    static func targetAllowed(_ card: AdvisorCard, target: Int?, state: RecruitState, context: RecruitContext) -> Bool {
        guard (context.evaluationVersion ?? 0) >= 11, card.cardID == absorptionID else { return true }
        guard supportsAbsorption(context), absorptionStats(state) != nil,
              let recipient = state.board.first(where: { $0.entity.entityId == target }),
              let tribes = context.definitions[recipient.cardID]?.races else { return false }
        return tribes.contains("ELEMENTAL") || tribes.contains("ALL")
    }

    static func battlecry(_ card: AdvisorCard, context: RecruitContext) -> RecruitEffects.Effect? {
        guard (context.evaluationVersion ?? 0) >= 11,
              card.cardID == "BG35_881" || card.cardID == "BG35_881_G" else { return nil }
        let count = card.cardID == "BG35_881_G" ? 2 : 1
        let text = count == 2 ? "Battlecry and Deathrattle: Get 2 Arcane Absorptions."
            : "Battlecry and Deathrattle: Get an Arcane Absorption."
        guard card.isMinion, context.definitions[card.cardID]?.type == "MINION",
              context.text(card.cardID) == text, supportsAbsorption(context) else {
            return .unsupported("Leyline Surfacer needs its exact Arcane Absorption reward")
        }
        return .token(absorptionID, count, toHand: true)
    }
}
