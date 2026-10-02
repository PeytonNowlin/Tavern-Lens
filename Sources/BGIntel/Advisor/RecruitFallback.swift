import Foundation

/// Short, contextual estimates when the bounded exact planner has no usable continuation.
/// These states are valuation sketches only: they are never passed to combat simulation.
public enum RecruitFallback {
    public static func suggestions(_ request: AdvisorRequest, context: RecruitContext,
                                   limitations: [String]) -> [AdvisorSuggestion] {
        guard context.policy.has(.fallbackAdvice), context.pendingChoice != true else { return [] }
        let initial = RecruitState(request: request, context: context)
        let baseline = RecruitPlanner.value(RecruitEffects.combatProjection(initial, context: context),
                                            request: request, context: context)
        let health = initial.input.playerBoard.player.hpLeft
        var options: [String: AdvisorSuggestion] = [:]
        func name(_ card: AdvisorCard) -> String { context.definitions[card.cardID]?.name ?? card.cardID }
        func consider(_ state: RecruitState, key: String, reason: String) {
            guard let first = state.steps.first else { return }
            let projected = RecruitEffects.combatProjection(state, context: context)
            let value = RecruitPlanner.value(projected, request: request, context: context)
            let cost = Double(state.steps.count) * 0.05
            let gain = value.total - baseline.total - cost
            guard gain > 0.75, gain.isFinite else { return }
            var suggestion = AdvisorSuggestion(rank: 0, action: first.action, targets: first.action.targets,
                reason: reason, confidence: .low, odds: nil, gain: gain,
                terms: AdvisorTerms(combat: value.tempo - baseline.tempo, lobby: nil,
                    build: value.scaling + value.synergy - baseline.scaling - baseline.synergy,
                    economy: value.economy - baseline.economy - cost))
            suggestion.continuation = state.steps.map(\.title)
            var seen: Set<String> = []
            suggestion.limitations = (state.limitations + projected.limitations + limitations
                + ["Estimate from known effects; combat outcome not verified"]).filter { seen.insert($0).inserted }
            if let old = options[key], old.gain >= gain { return }
            options[key] = suggestion
        }
        // A sale must make room or pay for a specific follow-up. Its lost stats, production,
        // attached gifts and contribution to the remaining engine all enter the same value.
        let sells = RecruitPlanner.actions(initial, context: context).filter { $0.kind == .sell }
        func starts(needsSale: Bool) -> [RecruitState] {
            guard needsSale else { return [initial] }
            return sells.compactMap { RecruitPlanner.applying($0, to: initial, context: context) }
        }
        for card in initial.shop where card.isMinion && context.definitions[card.cardID] != nil {
            let price = card.cost ?? AdvisorRequest.defaultMinionCost
            guard price >= 0, price <= initial.gold + AdvisorRequest.sellValue,
                  initial.hand.count < AdvisorRequest.handLimit,
                  RecruitEffects.isSupported(RecruitEffects.battlecry(card, context: context)) else { continue }
            for start in starts(needsSale: initial.board.count >= AdvisorRequest.boardLimit || price > initial.gold) {
                guard price <= start.gold,
                      let step = RecruitPlanner.actions(start, context: context).first(where: {
                          $0.kind == .buy && $0.entityID == card.entity.entityId
                      }), let bought = buying(step, state: start, context: context) else { continue }
                for played in playing(card.entity.entityId, state: bought, context: context) {
                    let sale = start.steps.first.map { $0.title + " to make room or fund " + name(card) + ". " } ?? ""
                    consider(played, key: "buy:\(card.entity.entityId)",
                        reason: sale + "Best estimated purchase from its observed stats, known effects and engine fit; reassess after each action")
                }
            }
        }
        for card in initial.hand where card.isMinion && !card.entity.locked
            && context.definitions[card.cardID] != nil {
            for start in starts(needsSale: initial.board.count >= AdvisorRequest.boardLimit) {
                for played in playing(card.entity.entityId, state: start, context: context) {
                    consider(played, key: "play:\(card.entity.entityId)",
                        reason: "Use the minion already in hand; compares its known strength and engine fit with the board space it needs")
                }
            }
        }
        // Keep the established one-hit survival boundary. No speculative sell-to-level route.
        if health > 15, initial.board.count >= 4,
           let level = RecruitPlanner.actions(initial, context: context).first(where: { $0.kind == .level }),
           let next = RecruitPlanner.applying(level, to: initial, context: context) {
            consider(next, key: "level", reason: "Open the next Tavern Tier while keeping your board; an economy estimate, not a verified survival advantage")
        }
        var ranked = options.sorted { a, b in
            a.value.gain == b.value.gain ? a.key < b.key : a.value.gain > b.value.gain
        }.prefix(3).map(\.value)
        if ranked.isEmpty {
            // A refresh is useful only if it leaves a purchase reserve. Never sell an engine
            // for an unknown shop, and never promise that refreshing supplies a build piece.
            let roll = RecruitPlanner.actions(initial, context: context).first { $0.kind == .roll }
            let canRoll: Bool
            if let roll, case .roll(let cost) = roll.action,
               let refreshed = RecruitPlanner.applying(roll, to: initial, context: context) {
                let value = RecruitPlanner.value(RecruitEffects.combatProjection(refreshed, context: context),
                                                 request: request, context: context)
                canRoll = initial.gold - cost >= 3 && value.tempo >= baseline.tempo
                    && value.scaling >= baseline.scaling
            } else { canRoll = false }
            let action: AdvisorAction = canRoll ? roll!.action : .keep
            let reason = canRoll
                ? "Reserve 3 Gold for a minion; refresh a shop with no clear known upgrade"
                : health <= 15 && request.levelCost != nil
                    ? "Keep your current strength; leveling has no verified survival margin at \(health) Health"
                    : "Keep the board: no affordable, supported replacement has a clear estimated benefit"
            var hold = AdvisorSuggestion(rank: 1, action: action, targets: action.targets,
                reason: reason, confidence: .low, odds: nil, gain: 0,
                terms: AdvisorTerms(combat: 0, lobby: nil, build: 0, economy: 0))
            hold.continuation = [action.title()]
            hold.limitations = limitations + ["Estimate from known effects; combat outcome not verified"]
            ranked = [hold]
        }
        for i in ranked.indices { ranked[i].rank = i + 1 }
        return ranked
    }

    private static func buying(_ step: RecruitStep, state: RecruitState, context: RecruitContext) -> RecruitState? {
        if let exact = RecruitPlanner.applying(step, to: state, context: context) { return exact }
        guard !RecruitEffects.triggersSupported(.buy, state: state, context: context),
              let index = state.shop.firstIndex(where: { $0.entity.entityId == step.entityID }),
              canEstimateBody(state.shop[index], state: state, context: context),
              state.hand.count < AdvisorRequest.handLimit else { return nil }
        let card = state.shop[index], price = card.cost ?? AdvisorRequest.defaultMinionCost
        guard price >= 0, price <= state.gold else { return nil }
        var next = state
        next.gold -= price; next.shop.remove(at: index); next.hand.append(card)
        next.steps.append(step)
        next.limitations.append("Buy triggers are unmodelled; reassess after buying")
        return next
    }

    private static func playing(_ entity: Int, state: RecruitState, context: RecruitContext) -> [RecruitState] {
        let steps = RecruitPlanner.actions(state, context: context).filter { $0.kind == .play && $0.entityID == entity }
        let exact = steps.compactMap { RecruitPlanner.applying($0, to: state, context: context) }
        if !exact.isEmpty { return exact }
        guard !RecruitEffects.triggersSupported(.play, state: state, context: context),
              let index = state.hand.firstIndex(where: { $0.entity.entityId == entity }),
              let step = steps.first, state.board.count < AdvisorRequest.boardLimit,
              canEstimateBody(state.hand[index], state: state, context: context) else { return [] }
        var next = state
        var card = next.hand.remove(at: index)
        guard RecruitPlayedMinions.prepare(&card, before: state, state: &next, context: context) else { return [] }
        guard RecruitDiscardEffects.synchronizeHammer(card: &card, state: next, context: context) else { return [] }
        next.board.append(card)
        guard RecruitCardEffects.afterPlay(before: state, state: &next, context: context) else { return [] }
        next.steps.append(step)
        RecruitMechanics.playedCard(before: state, state: &next, context: context)
        next.limitations.append("Play triggers are unmodelled; estimate uses observed stats and known ongoing effects")
        return [next]
    }

    private static func canEstimateBody(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> Bool {
        guard card.isMinion, !card.entity.locked, context.definitions[card.cardID] != nil,
              case .none = RecruitEffects.battlecry(card, context: context),
              !card.entity.enchantments.contains(where: { $0.cardId == "BG36_308e" }) else { return false }
        // Do not invent a triple's merged stats, lost board slots or generated reward when
        // an unknown trigger prevented the real transition from resolving it.
        return card.golden || (state.board + state.hand).filter {
            !$0.golden && $0.entity.entityId != card.entity.entityId && context.base($0.cardID) == context.base(card.cardID)
        }.count < 2
    }
}
