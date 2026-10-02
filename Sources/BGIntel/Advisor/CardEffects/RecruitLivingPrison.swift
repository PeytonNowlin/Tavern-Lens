/// Living Prison's historical stat enchantment is already included in the observed
/// body. Only explicit tag 4945, or an activation in this plan, arms a future buy.
enum RecruitLivingPrison: RecruitCardEffect {
    static let cardIDs: Set<String> = ["BG36_180", "BG36_180_G"]
    static let since = AdvisorPolicy.Feature.livingPrison.introduced
    static let requiresObservedActivationCost = true

    private static func isPrison(_ id: String) -> Bool { cardIDs.contains(id) }

    static func multiplier(_ card: AdvisorCard, context: RecruitContext) -> Int? {
        guard card.isMinion, context.definitions[card.cardID]?.type == "MINION",
              !RecruitCardEffects.activatesTwice(card, context) else { return nil }
        switch (card.cardID, context.text(card.cardID)) {
        case ("BG36_180", "Activate (1): Gain the stats of the next minion you buy this turn."): return 1
        case ("BG36_180_G", "Activate (1): Gain double the stats of the next minion you buy this turn."): return 2
        default: return nil
        }
    }

    static func activationRecognized(_ card: AdvisorCard, context: RecruitContext) -> Bool {
        multiplier(card, context: context) != nil
    }

    static func activationLimitation(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> String? {
        guard state.pendingPrisonBuys[card.entity.entityId] == nil else { return nil }
        return "Living Prison pending buy state is unknown; observe activation or tag 4945"
    }

    static func activationActions(_ card: AdvisorCard, index: Int, state: RecruitState, context: RecruitContext) -> [RecruitStep]? {
        guard multiplier(card, context: context) != nil else { return nil }
        guard let available = RecruitCardEffects.availableActivation(card.entity.entityId, state: state, context: context, observedCost: true),
              state.pendingPrisonBuys[card.entity.entityId] != true else { return [] }
        return [RecruitCardEffects.untargetedActivation(card, index: index, cost: available.cost, context: context)]
    }

    static func activate(_ step: RecruitStep, source: AdvisorCard, state: inout RecruitState, context: RecruitContext) -> Bool? {
        guard multiplier(source, context: context) != nil else { return nil }
        guard let available = RecruitCardEffects.availableActivation(step.entityID, state: state, context: context, observedCost: true),
              step.targetID == nil, state.pendingPrisonBuys[step.entityID] != true else { return false }
        state.pendingPrisonBuys[step.entityID] = true
        RecruitCardEffects.spendActivation(available, entityID: step.entityID, state: &state)
        return true
    }

    static func afterBuy(_ bought: AdvisorCard, state: inout RecruitState, context: RecruitContext) -> Bool {
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

    static func afterSell(_ sold: AdvisorCard, state: inout RecruitState, context: RecruitContext) {
        state.pendingPrisonBuys.removeValue(forKey: sold.entity.entityId)
    }

    static func canTriple(_ cards: [AdvisorCard], state: RecruitState, context: RecruitContext) -> Bool {
        guard cards.contains(where: { isPrison($0.cardID) }) else { return true }
        // An armed effect's transfer through a triple has not been validated. Resolve
        // its buy first rather than carrying a guessed pending effect to the golden.
        return cards.allSatisfy { state.pendingPrisonBuys[$0.entity.entityId] == false }
    }

    static func afterTriple(_ cardID: String, consumed: Set<Int>, golden: AdvisorCard, state: inout RecruitState, context: RecruitContext) {
        guard isPrison(cardID) else { return }
        for entityID in consumed { state.pendingPrisonBuys.removeValue(forKey: entityID) }
        state.pendingPrisonBuys[golden.entity.entityId] = false
    }

    static func beforeCombatProjection(_ state: inout RecruitState, context: RecruitContext) {
        for id in state.pendingPrisonBuys.keys { state.pendingPrisonBuys[id] = false }
    }
}
