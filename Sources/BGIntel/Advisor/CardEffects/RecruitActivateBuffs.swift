/// Deterministic, non-discard Activate effects added in policy 7. Readiness and prices
/// still come from the log; unknown rewards and ambiguous selections are not invented.
enum RecruitSuspiciousPrisonguard: RecruitCardEffect {
    static let cardIDs: Set<String> = ["BG36_345", "BG36_345_G"]
    static let since = 7

    private static func amount(_ card: AdvisorCard, context: RecruitContext) -> Int? {
        guard !RecruitCardEffects.activatesTwice(card, context) else { return nil }
        switch (card.cardID, context.text(card.cardID)) {
        case ("BG36_345", "Activate (1): Give another minion +3/+3."): return 3
        case ("BG36_345_G", "Activate (1): Give another minion +6/+6."): return 6
        default: return nil
        }
    }

    static func activationRecognized(_ card: AdvisorCard, context: RecruitContext) -> Bool {
        amount(card, context: context) != nil
    }

    static func activationActions(_ card: AdvisorCard, index: Int, state: RecruitState, context: RecruitContext) -> [RecruitStep]? {
        guard amount(card, context: context) != nil else { return nil }
        guard let available = RecruitCardEffects.availableActivation(card.entity.entityId, state: state, context: context) else { return [] }
        return state.board.enumerated().filter { $0.element.entity.entityId != card.entity.entityId }.map {
            RecruitCardEffects.targetedActivation(card, index: index, cost: available.cost, target: $0.element,
                                                  position: AdvisorTarget(.board, $0.offset), context: context)
        }
    }

    static func activate(_ step: RecruitStep, source: AdvisorCard, state: inout RecruitState, context: RecruitContext) -> Bool? {
        guard let amount = amount(source, context: context) else { return nil }
        guard let available = RecruitCardEffects.availableActivation(step.entityID, state: state, context: context),
              step.targetID != step.entityID,
              let target = state.board.firstIndex(where: { $0.entity.entityId == step.targetID }) else { return false }
        RecruitEffects.buff(&state.board[target], attack: amount, health: amount)
        RecruitCardEffects.spendActivation(available, entityID: step.entityID, state: &state)
        return true
    }
}

enum RecruitDecoyConjurer: RecruitCardEffect {
    static let cardIDs: Set<String> = ["BG36_354"]
    static let since = 7

    private static func recognized(_ card: AdvisorCard, context: RecruitContext) -> Bool {
        !RecruitCardEffects.activatesTwice(card, context)
            && context.text(card.cardID) == "Activate (2): Steal the highest-Attack minion in the Tavern."
    }

    private static func highest(_ state: RecruitState) -> [AdvisorCard] {
        let minions = state.shop.filter(\.isMinion)
        guard let attack = minions.map({ $0.entity.attack }).max() else { return [] }
        return minions.filter { $0.entity.attack == attack }
    }

    static func activationRecognized(_ card: AdvisorCard, context: RecruitContext) -> Bool {
        recognized(card, context: context)
    }

    static func activationLimitation(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> String? {
        guard recognized(card, context: context), highest(state).count > 1,
              let available = context.activations?[card.entity.entityId], available.ready,
              available.cost <= state.gold, !state.usedActivations.contains(card.entity.entityId),
              state.hand.count < AdvisorRequest.handLimit else { return nil }
        return "Unmodelled Activate: \(RecruitPlanner.name(card, context)) (highest-Attack tie)"
    }

    static func activationActions(_ card: AdvisorCard, index: Int, state: RecruitState, context: RecruitContext) -> [RecruitStep]? {
        guard recognized(card, context: context) else { return nil }
        let high = highest(state)
        guard let available = RecruitCardEffects.availableActivation(card.entity.entityId, state: state, context: context),
              state.hand.count < AdvisorRequest.handLimit, high.count == 1, let target = high.first,
              let shopIndex = state.shop.firstIndex(where: { $0.entity.entityId == target.entity.entityId }) else { return [] }
        return [RecruitCardEffects.targetedActivation(card, index: index, cost: available.cost, target: target,
                                                      position: AdvisorTarget(.shop, shopIndex), context: context)]
    }

    static func activate(_ step: RecruitStep, source: AdvisorCard, state: inout RecruitState, context: RecruitContext) -> Bool? {
        guard recognized(source, context: context) else { return nil }
        let high = highest(state)
        guard let available = RecruitCardEffects.availableActivation(step.entityID, state: state, context: context),
              state.hand.count < AdvisorRequest.handLimit, high.count == 1,
              high.first?.entity.entityId == step.targetID,
              let target = state.shop.firstIndex(where: { $0.entity.entityId == step.targetID }) else { return false }
        // A steal acquires the observed card, without firing purchase or battlecry effects.
        // RecruitPlanner resolves any resulting triple after the activation.
        state.hand.append(state.shop.remove(at: target))
        RecruitCardEffects.spendActivation(available, entityID: step.entityID, state: &state)
        return true
    }
}

enum RecruitFruitVendor: RecruitCardEffect {
    static let cardIDs: Set<String> = ["BG36_346", "BG36_346_G"]
    static let since = 8
    static let banana = "BG28_897"

    private static func count(_ card: AdvisorCard, context: RecruitContext) -> Int? {
        guard !RecruitCardEffects.activatesTwice(card, context),
              context.definitions[banana]?.type == "BATTLEGROUND_SPELL",
              context.text(banana) == "Give a minion +2/+2." else { return nil }
        switch (card.cardID, context.text(card.cardID)) {
        case ("BG36_346", "Activate (1): Get 2 Tavern Dish Bananas."): return 2
        case ("BG36_346_G", "Activate (1): Get 4 Tavern Dish Bananas."): return 4
        default: return nil
        }
    }

    static func activationRecognized(_ card: AdvisorCard, context: RecruitContext) -> Bool {
        count(card, context: context) != nil
    }

    static func activationActions(_ card: AdvisorCard, index: Int, state: RecruitState, context: RecruitContext) -> [RecruitStep]? {
        guard let count = count(card, context: context) else { return nil }
        guard let available = RecruitCardEffects.availableActivation(card.entity.entityId, state: state, context: context),
              state.hand.count + state.unknownRewards + count <= AdvisorRequest.handLimit else { return [] }
        return [RecruitCardEffects.untargetedActivation(card, index: index, cost: available.cost, context: context)]
    }

    static func activate(_ step: RecruitStep, source: AdvisorCard, state: inout RecruitState, context: RecruitContext) -> Bool? {
        guard let count = count(source, context: context) else { return nil }
        guard let available = RecruitCardEffects.availableActivation(step.entityID, state: state, context: context),
              step.targetID == nil,
              state.hand.count + state.unknownRewards + count <= AdvisorRequest.handLimit else { return false }
        // These rewards are known cards. Continue into the ordinary hand-spell path,
        // which applies their buffs and spell triggers when each Banana is actually cast.
        guard RecruitEffects.apply(.token(banana, count, toHand: true), target: nil,
                                   state: &state, context: context) else { return false }
        RecruitCardEffects.spendActivation(available, entityID: step.entityID, state: &state)
        return true
    }
}
