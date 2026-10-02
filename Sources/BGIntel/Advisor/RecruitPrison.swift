/// Living Prison's historical stat enchantment is already included in the observed
/// body. Only explicit tag 4945, or an activation in this plan, arms a future buy.
enum RecruitPrison {
    static func enabled(_ context: RecruitContext) -> Bool { context.policy.has(.livingPrison) }
    static func isPrison(_ id: String) -> Bool { id == "BG36_180" || id == "BG36_180_G" }

    static func multiplier(_ card: AdvisorCard, context: RecruitContext) -> Int? {
        guard enabled(context), card.isMinion, context.definitions[card.cardID]?.type == "MINION",
              !RecruitMechanics.gifts(card, context).contains("This minion's Activate triggers twice.") else { return nil }
        switch (card.cardID, context.text(card.cardID)) {
        case ("BG36_180", "Activate (1): Gain the stats of the next minion you buy this turn."): return 1
        case ("BG36_180_G", "Activate (1): Gain double the stats of the next minion you buy this turn."): return 2
        default: return nil
        }
    }

    static func limitation(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> String? {
        guard enabled(context), isPrison(card.cardID), state.pendingPrisonBuys[card.entity.entityId] == nil else { return nil }
        return "Living Prison pending buy state is unknown; observe activation or tag 4945"
    }

    static func afterBuy(_ bought: AdvisorCard, state: inout RecruitState, context: RecruitContext) -> Bool {
        guard enabled(context) else { return true }
        guard bought.isMinion, bought.entity.attack >= 0, bought.entity.health > 0 else { return false }
        for index in state.board.indices where isPrison(state.board[index].cardID) {
            let card = state.board[index], id = card.entity.entityId
            guard let pending = state.pendingPrisonBuys[id] else { return false }
            guard !pending || multiplier(card, context: context) != nil else { return false }
            if pending, let repeats = multiplier(card, context: context) {
                RecruitEffects.buff(&state.board[index], attack: bought.entity.attack * repeats, health: bought.entity.health * repeats)
                state.pendingPrisonBuys[id] = false
            }
        }
        if isPrison(bought.cardID), multiplier(bought, context: context) != nil {
            // A Tavern purchase cannot have been activated by this player. A held
            // instance, including one returned to hand, keeps its separate observation.
            state.pendingPrisonBuys[bought.entity.entityId] = false
        }
        return true
    }

    static func canTriple(_ cards: [AdvisorCard], state: RecruitState, context: RecruitContext) -> Bool {
        guard enabled(context), cards.contains(where: { isPrison($0.cardID) }) else { return true }
        // An armed effect's transfer through a triple has not been validated. Resolve
        // its buy first rather than carrying a guessed pending effect to the golden.
        return cards.allSatisfy { state.pendingPrisonBuys[$0.entity.entityId] == false }
    }
}
