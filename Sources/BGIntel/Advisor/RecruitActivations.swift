/// Deterministic, non-discard Activate effects added in policy 7. Readiness and prices
/// still come from the log; unknown rewards and ambiguous selections are not invented.
enum RecruitActivations {
    private enum Effect {
        case buff(Int), stealHighest, bananas(Int), prison
    }

    private static func effect(_ card: AdvisorCard, context: RecruitContext) -> Effect? {
        guard context.policy.has(.activateEffects),
              !RecruitMechanics.gifts(card, context).contains("This minion's Activate triggers twice.") else { return nil }
        if RecruitPrison.multiplier(card, context: context) != nil { return .prison }
        switch (card.cardID, context.text(card.cardID)) {
        case ("BG36_345", "Activate (1): Give another minion +3/+3."): return .buff(3)
        case ("BG36_345_G", "Activate (1): Give another minion +6/+6."): return .buff(6)
        case ("BG36_354", "Activate (2): Steal the highest-Attack minion in the Tavern."): return .stealHighest
        case ("BG36_346", "Activate (1): Get 2 Tavern Dish Bananas."),
             ("BG36_346_G", "Activate (1): Get 4 Tavern Dish Bananas."):
            guard context.policy.has(.bananaActivate),
                  context.definitions["BG28_897"]?.type == "BATTLEGROUND_SPELL",
                  context.text("BG28_897") == "Give a minion +2/+2." else { return nil }
            return .bananas(card.cardID == "BG36_346_G" ? 4 : 2)
        default: return nil
        }
    }

    static func supported(_ card: AdvisorCard, context: RecruitContext) -> Bool {
        effect(card, context: context) != nil || RecruitLionfish.recognized(card, context: context)
    }

    private static func highest(_ state: RecruitState) -> [AdvisorCard] {
        let minions = state.shop.filter(\.isMinion)
        guard let attack = minions.map({ $0.entity.attack }).max() else { return [] }
        return minions.filter { $0.entity.attack == attack }
    }

    static func limitation(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> String? {
        if let reason = RecruitPrison.limitation(card, state: state, context: context) { return reason }
        if let reason = RecruitLionfish.limitation(card, state: state, context: context) { return reason }
        guard case .stealHighest? = effect(card, context: context), highest(state).count > 1,
              let available = context.activations?[card.entity.entityId], available.ready,
              available.cost <= state.gold, !state.usedActivations.contains(card.entity.entityId),
              state.hand.count < AdvisorRequest.handLimit else { return nil }
        return "Unmodelled Activate: \(RecruitPlanner.name(card, context)) (highest-Attack tie)"
    }

    /// Nil leaves legacy discard activations to their original handler. An empty list
    /// means this supported effect currently has no safe legal target.
    static func actions(_ card: AdvisorCard, index: Int, state: RecruitState, context: RecruitContext) -> [RecruitStep]? {
        if let actions = RecruitLionfish.actions(card, index: index, state: state, context: context) { return actions }
        guard let effect = effect(card, context: context) else { return nil }
        guard let available = context.activations?[card.entity.entityId], available.ready,
              available.cost >= 0, available.cost <= state.gold,
              !state.usedActivations.contains(card.entity.entityId) else { return [] }
        let targets: [(AdvisorCard, AdvisorTarget)]
        switch effect {
        case .prison:
            guard available.costObserved != false, state.pendingPrisonBuys[card.entity.entityId] != true else { return [] }
            let action = AdvisorAction.activateUntargeted(board: index, cardID: card.cardID, cost: available.cost)
            return [RecruitStep(kind: .activate, entityID: card.entity.entityId, action: action,
                title: action.title { context.definitions[$0]?.name ?? $0 })]
        case .bananas(let count):
            guard state.hand.count + state.unknownRewards + count <= AdvisorRequest.handLimit else { return [] }
            let action = AdvisorAction.activateUntargeted(board: index, cardID: card.cardID, cost: available.cost)
            return [RecruitStep(kind: .activate, entityID: card.entity.entityId, action: action,
                title: action.title { context.definitions[$0]?.name ?? $0 })]
        case .buff:
            targets = state.board.enumerated().filter { $0.element.entity.entityId != card.entity.entityId }
                .map { ($0.element, AdvisorTarget(.board, $0.offset)) }
        case .stealHighest:
            let high = highest(state)
            guard state.hand.count < AdvisorRequest.handLimit, high.count == 1,
                  let target = high.first,
                  let shopIndex = state.shop.firstIndex(where: { $0.entity.entityId == target.entity.entityId }) else { return [] }
            targets = [(target, AdvisorTarget(.shop, shopIndex))]
        }
        return targets.map { target, position in
            let action = AdvisorAction.activateMinion(board: index, cardID: card.cardID, cost: available.cost,
                target: position, targetCardID: target.cardID)
            return RecruitStep(kind: .activate, entityID: card.entity.entityId, targetID: target.entity.entityId,
                action: action, title: action.title { context.definitions[$0]?.name ?? $0 })
        }
    }

    static func apply(_ step: RecruitStep, state: inout RecruitState, context: RecruitContext) -> Bool? {
        if let handled = RecruitLionfish.apply(step, state: &state, context: context) { return handled }
        guard let source = state.board.first(where: { $0.entity.entityId == step.entityID }),
              let effect = effect(source, context: context) else { return nil }
        guard let available = context.activations?[step.entityID], available.ready,
              available.cost >= 0, available.cost <= state.gold,
              !state.usedActivations.contains(step.entityID) else { return false }
        switch effect {
        case .prison:
            guard available.costObserved != false, step.targetID == nil,
                  state.pendingPrisonBuys[step.entityID] != true else { return false }
            state.pendingPrisonBuys[step.entityID] = true
        case .bananas(let count):
            guard step.targetID == nil,
                  state.hand.count + state.unknownRewards + count <= AdvisorRequest.handLimit else { return false }
            // These rewards are known cards. Continue into the ordinary hand-spell path,
            // which applies their buffs and spell triggers when each Banana is actually cast.
            guard RecruitEffects.apply(.token("BG28_897", count, toHand: true), target: nil,
                                       state: &state, context: context) else { return false }
        case .buff(let amount):
            guard step.targetID != step.entityID,
                  let target = state.board.firstIndex(where: { $0.entity.entityId == step.targetID }) else { return false }
            RecruitEffects.buff(&state.board[target], attack: amount, health: amount)
        case .stealHighest:
            let high = highest(state)
            guard state.hand.count < AdvisorRequest.handLimit, high.count == 1,
                  high.first?.entity.entityId == step.targetID,
                  let target = state.shop.firstIndex(where: { $0.entity.entityId == step.targetID }) else { return false }
            // A steal acquires the observed card, without firing purchase or battlecry effects.
            // RecruitPlanner resolves any resulting triple after the activation.
            state.hand.append(state.shop.remove(at: target))
        }
        state.gold -= available.cost
        state.input.playerBoard.player.globalInfo["GoldSpentThisGame", default: 0] += available.cost
        state.usedActivations.insert(step.entityID)
        return true
    }
}
