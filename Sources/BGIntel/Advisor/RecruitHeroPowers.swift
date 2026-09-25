import Foundation

/// Recruit powers with unrevealed rewards stop the plan at the information boundary.
/// Their option value never supplies a fictional minion or combat result.
public enum RecruitHeroPowers {
    enum Reward {
        case spy, ritual
        var handSlots: Int { self == .ritual ? 2 : 1 }
    }

    static func reward(_ id: String, _ context: RecruitContext) -> Reward? {
        switch (id, context.text(id)) {
        case ("BG21_HERO_010p", "Discover a plain copy of a minion from your next opponent's warband."): return .spy
        case ("BG36_HERO_002p", "Get 2 random minions. When you play one, discard the other."): return .ritual
        default: return nil
        }
    }

    static func supported(_ id: String, _ context: RecruitContext) -> Bool {
        reward(id, context) != nil || RecruitEffects.isSupported(RecruitEffects.effect(context.text(id)))
    }

    static func available(_ id: String, state: RecruitState, context: RecruitContext) -> Bool {
        guard let reward = reward(id, context) else { return supported(id, context) }
        // Don't recommend burning a reward into a full hand.
        return state.hand.count + state.unknownRewards + reward.handSlots <= AdvisorRequest.handLimit
    }

    static func apply(_ id: String, cost: Int, target: Int?, state: inout RecruitState, context: RecruitContext) -> Bool {
        guard available(id, state: state, context: context) else { return false }
        if reward(id, context) != nil {
            // The reward goes to hand, so don't sell purely for speculative board room.
            if state.steps.contains(where: { $0.kind == .sell }), state.gold - 1 >= cost { return false }
            state.terminal = true
            state.limitations.append(explanation(id, context: context)!)
            return true
        }
        return RecruitEffects.apply(RecruitEffects.effect(context.text(id)), target: target, state: &state, context: context)
    }

    static func resolveLinkedDiscard(_ played: AdvisorCard, state: inout RecruitState, context: RecruitContext) -> Bool {
        guard played.entity.enchantments.contains(where: { $0.cardId == "BG36_308e" }) else { return true }
        // Old captures omit the batch: refuse an invented pairing.
        guard let linked = context.linkedDiscards?[played.entity.entityId] else { return false }
        for id in linked {
            guard let index = state.hand.firstIndex(where: { $0.entity.entityId == id }) else { continue }
            let discarded = state.hand.remove(at: index)
            guard RecruitMechanics.discardEffects(discarded, state: &state, context: context) else { return false }
        }
        if let index = state.board.firstIndex(where: { $0.entity.entityId == played.entity.entityId }) {
            state.board[index].entity.enchantments.removeAll { $0.cardId == "BG36_308e" }
        }
        return true
    }

    public static func explanation(_ id: String, context: RecruitContext) -> String? {
        switch reward(id, context) {
        case .spy: return "Discover from your next opponent; choices unknown. Choose, then reassess"
        case .ritual: return "Get two random minions; playing one discards the other. Reveal them, then reassess"
        case nil: return nil
        }
    }

    static func optionValue(_ state: RecruitState, context: RecruitContext, horizon: Double) -> Double {
        guard let step = state.steps.last, step.kind == .power,
              let power = state.input.playerBoard.player.heroPowers.first(where: { $0.entityId == step.entityID }),
              let reward = reward(power.cardId, context) else { return 0 }
        let room = state.board.count < AdvisorRequest.boardLimit ? 1.0 : 0.35
        // Tier is a conservative local proxy, never the last opponent's card quality.
        // Ritual retains one playable minion, not two independent bodies.
        let choice = reward == .spy ? 0.5 : 0.0
        return (2 + Double(state.tier) * 1.5 + choice) * room * min(1, horizon)
    }
}
