import Foundation

/// A bounded plan, its strategic value, and an honest combat projection. Search states never
/// mutate the request, so every recommendation can be inspected and replayed.
public struct RecruitPlan: Sendable {
    public var state: RecruitState
    public var projection: RecruitState
    public var value: RecruitValue
    public var id: String { state.steps.map(\.id).joined(separator: "/") }
}

public struct RecruitValue: Sendable {
    public var tempo: Double = 0
    public var scaling: Double = 0
    public var economy: Double = 0
    public var synergy: Double = 0
    public var total: Double { tempo + scaling + economy + synergy }
}

public struct RecruitSearch: Sendable {
    public var baseline: RecruitPlan
    public var plans: [RecruitPlan]
    public var limitations: [String]
    public var expanded: Int
}

public enum RecruitPlanner {
    public struct Budget: Sendable {
        public var depth: Int
        public var width: Int
        public var expansions: Int
        public init(depth: Int = 5, width: Int = 18, expansions: Int = 1800) {
            self.depth = depth; self.width = width; self.expansions = expansions
        }
    }

    static func name(_ card: AdvisorCard, _ context: RecruitContext) -> String {
        context.definitions[card.cardID]?.name ?? card.cardID
    }

    public static func actions(_ state: RecruitState, context: RecruitContext, canFreeze: Bool = true) -> [RecruitStep] {
        guard !state.terminal else { return [] }
        var actions: [RecruitStep] = []
        for (i, card) in state.shop.enumerated() where state.hand.count < AdvisorRequest.handLimit {
            let price = card.isMinion ? card.cost ?? 3 : card.cost ?? Int.max
            guard price <= state.gold else { continue }
            if card.isMinion {
                actions.append(RecruitStep(kind: .buy, entityID: card.entity.entityId,
                    action: .buy(shop: i, cardID: card.cardID, place: state.board.count), title: "Buy \(name(card, context))"))
            } else {
                spellActions(card, index: i, source: .shop, state: state, context: context, into: &actions)
            }
        }
        for (i, card) in state.hand.enumerated() where !card.entity.locked {
            if card.isMinion, state.board.count < AdvisorRequest.boardLimit {
                let effect = RecruitEffects.battlecry(card, context: context)
                guard RecruitEffects.isSupported(effect) else { continue }
                let targets: [Int?] = RecruitEffects.needsTarget(effect) ? state.board.map { $0.entity.entityId } : [nil]
                for target in targets {
                    actions.append(RecruitStep(kind: .play, entityID: card.entity.entityId, targetID: target,
                        action: .play(hand: i, cardID: card.cardID, place: state.board.count),
                        title: "Play \(name(card, context))" + target.map { id in " on \(state.board.first { $0.entity.entityId == id }.map { name($0, context) } ?? "minion")" } .orEmpty))
                }
            } else if !card.isMinion {
                spellActions(card, index: i, source: .hand, state: state, context: context, into: &actions)
            }
        }
        // Every legal sell is considered. Small engine cards are never preselected as weakest.
        for (i, card) in state.board.enumerated() where state.board.count > 1 {
            actions.append(RecruitStep(kind: .sell, entityID: card.entity.entityId,
                action: .sell(board: i, cardID: card.cardID), title: "Sell \(name(card, context))"))
        }
        for (i, card) in state.board.enumerated() {
            guard let availability = context.activations?[card.entity.entityId], availability.ready,
                  availability.cost <= state.gold, !state.usedActivations.contains(card.entity.entityId),
                  RecruitMechanics.activationSupported(card, context) else { continue }
            for (h, discarded) in state.hand.enumerated() where !discarded.entity.locked {
                let action = AdvisorAction.activate(board: i, cardID: card.cardID, cost: availability.cost,
                    discard: h, discardedCardID: discarded.cardID)
                actions.append(RecruitStep(kind: .activate, entityID: card.entity.entityId,
                    targetID: discarded.entity.entityId, action: action,
                    title: action.title { context.definitions[$0]?.name ?? $0 }))
            }
        }
        for power in state.input.playerBoard.player.heroPowers where !power.used && power.locked == 0 {
            guard let cost = context.powerCosts[power.cardId], cost <= state.gold else { continue }
            let effect = RecruitEffects.effect(context.text(power.cardId))
            guard RecruitEffects.isSupported(effect) else { continue }
            let targets: [Int?] = RecruitEffects.needsTarget(effect) ? state.board.map { $0.entity.entityId } : [nil]
            for target in targets {
                let i = state.board.firstIndex { $0.entity.entityId == target }
                let targetCard = i.map { state.board[$0].cardID }
                let action = AdvisorAction.heroPower(cardID: power.cardId, cost: cost, target: i, targetCardID: targetCard)
                actions.append(RecruitStep(kind: .power, entityID: power.entityId, targetID: target,
                    action: action, title: action.title { context.definitions[$0]?.name ?? $0 }))
            }
        }
        if let cost = state.levelCost, cost <= state.gold, state.tier < 6 {
            actions.append(RecruitStep(kind: .level, action: .level(cost: cost, toTier: state.tier + 1), title: "Level to tier \(state.tier + 1)"))
        }
        if let cost = state.rollCost, cost <= state.gold || state.freeRolls > 0 {
            actions.append(RecruitStep(kind: .roll, action: .roll(cost: state.freeRolls > 0 ? 0 : cost), title: "Refresh, then reassess the new shop"))
        }
        if canFreeze, !state.frozen, !state.shop.isEmpty {
            actions.append(RecruitStep(kind: .freeze, action: .freeze, title: "Freeze the tavern"))
        }
        // Ordering is explored once, not repeatedly through equivalent permutations.
        if state.steps.isEmpty, state.board.count > 1 {
            for i in state.board.indices {
                for to in [0, state.board.count - 1] where i != to {
                    let card = state.board[i]
                    actions.append(RecruitStep(kind: .move, entityID: card.entity.entityId, position: to,
                        action: .move(board: i, cardID: card.cardID, to: to), title: "Move \(name(card, context)) to slot \(to + 1)"))
                }
            }
        }
        return actions
    }

    static func spellEffect(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> RecruitEffects.Effect {
        if card.cardID == "BG20_GEM" {
            return .buff(1 + (state.input.playerBoard.player.globalInfo["BloodGemAttackBonus"] ?? 0),
                         1 + (state.input.playerBoard.player.globalInfo["BloodGemHealthBonus"] ?? 0), all: false)
        }
        return RecruitEffects.effect(context.text(card.cardID))
    }

    static func spellActions(_ card: AdvisorCard, index: Int, source: AdvisorAction.SpellSource,
                             state: RecruitState, context: RecruitContext, into actions: inout [RecruitStep]) {
        let effect = spellEffect(card, state: state, context: context)
        guard RecruitEffects.isSupported(effect) else { return }
        let targets: [Int?] = RecruitEffects.needsTarget(effect) ? state.board.map { $0.entity.entityId } : [nil]
        for target in targets {
            let i = state.board.firstIndex { $0.entity.entityId == target }
            let action = AdvisorAction.cast(from: source, index: index, cardID: card.cardID, option: 0,
                                            target: i, targetCardID: i.map { state.board[$0].cardID })
            actions.append(RecruitStep(kind: .spell, entityID: card.entity.entityId, targetID: target,
                                       action: action, title: action.title { context.definitions[$0]?.name ?? $0 }))
        }
    }

    /// Returns nil for illegal or unsupported transitions. All edits are to a value copy.
    public static func applying(_ step: RecruitStep, to original: RecruitState, context: RecruitContext) -> RecruitState? {
        guard !original.terminal, RecruitEffects.triggersSupported(step.kind, state: original, context: context) else { return nil }
        var s = original
        switch step.kind {
        case .buy:
            guard let i = s.shop.firstIndex(where: { $0.entity.entityId == step.entityID }), s.hand.count < 10 else { return nil }
            let card = s.shop[i], cost = card.cost ?? 3
            guard card.isMinion, cost <= s.gold, context.definitions[card.cardID] != nil,
                  RecruitEffects.isSupported(RecruitEffects.battlecry(card, context: context)) else { return nil }
            s.gold -= cost; s.shop.remove(at: i); s.hand.append(card)
            guard RecruitEffects.triples(state: &s, context: context) else { return nil }
        case .play:
            guard let i = s.hand.firstIndex(where: { $0.entity.entityId == step.entityID }), s.board.count < 7 else { return nil }
            let card = s.hand.remove(at: i)
            guard card.isMinion, !card.entity.locked else { return nil }
            s.board.append(card)
            for _ in 0..<RecruitEffects.battlecryRepeats(original, context: context) {
                guard RecruitEffects.apply(RecruitEffects.battlecry(card, context: context), target: step.targetID, state: &s, context: context) else { return nil }
                if context.text(card.cardID).contains("Battlecry") {
                    RecruitMechanics.counterBuffs("Battlecry you've triggered", state: &s, context: context)
                }
            }
            if card.golden, s.pendingDiscover > 0 {
                s.pendingDiscover -= 1; s.terminal = true
                s.limitations.append("Triple reward is unknown; choose it and replan")
            }
        case .sell:
            guard let i = s.board.firstIndex(where: { $0.entity.entityId == step.entityID }), s.board.count > 1 else { return nil }
            let card = s.board.remove(at: i)
            guard RecruitEffects.apply(RecruitEffects.sell(card, context: context), target: nil, state: &s, context: context) else { return nil }
            s.gold += 1
        case .spell:
            let inShop = s.shop.firstIndex { $0.entity.entityId == step.entityID }
            let inHand = s.hand.firstIndex { $0.entity.entityId == step.entityID }
            guard let card = inShop.map({ s.shop[$0] }) ?? inHand.map({ s.hand[$0] }), !card.isMinion else { return nil }
            let cost = inShop == nil ? 0 : card.cost ?? Int.max
            guard cost <= s.gold else { return nil }
            s.gold -= cost
            if let i = inShop { s.shop.remove(at: i) }; if let i = inHand { s.hand.remove(at: i) }
            let effect = spellEffect(card, state: s, context: context)
            var repeats = 1
            if card.cardID == "BG20_GEM" {
                for c in s.board {
                    let t = context.text(c.cardID)
                    if t == "Blood Gems played from your hand cast an extra time." { repeats += 1 }
                    else if t.lowercased().contains("blood gems played") { return nil }
                }
            }
            for _ in 0..<repeats {
                guard RecruitEffects.apply(effect, target: step.targetID, state: &s, context: context) else { return nil }
                s.input.playerBoard.player.globalInfo["SpellsCastThisGame", default: 0] += 1
                if card.cardID != "BG20_GEM" {
                    RecruitMechanics.counterBuffs("Tavern spell you've cast", state: &s, context: context)
                }
            }
        case .activate:
            guard RecruitMechanics.activate(step, state: &s, context: context) else { return nil }
        case .power:
            guard let i = s.input.playerBoard.player.heroPowers.firstIndex(where: { $0.entityId == step.entityID }) else { return nil }
            let p = s.input.playerBoard.player.heroPowers[i]
            guard !p.used, p.locked == 0, let cost = context.powerCosts[p.cardId], cost <= s.gold else { return nil }
            guard RecruitEffects.apply(RecruitEffects.effect(context.text(p.cardId)), target: step.targetID, state: &s, context: context) else { return nil }
            s.gold -= cost; s.input.playerBoard.player.heroPowers[i].used = true
        case .level:
            guard let cost = s.levelCost, cost <= s.gold, s.tier < 6 else { return nil }
            s.gold -= cost; s.tier += 1; s.levelCost = nil
        case .roll:
            guard let cost = s.rollCost, cost <= s.gold || s.freeRolls > 0 else { return nil }
            if s.freeRolls > 0 { s.freeRolls -= 1 } else { s.gold -= cost }
            s.terminal = true; s.shop = []
            s.limitations.append("Next shop unknown; refresh is a search decision, not a promised hit")
        case .freeze:
            guard !s.frozen, !s.shop.isEmpty else { return nil }
            s.frozen = true; s.terminal = true
        case .move:
            guard let i = s.board.firstIndex(where: { $0.entity.entityId == step.entityID }),
                  let to = step.position, s.board.indices.contains(to) else { return nil }
            let card = s.board.remove(at: i); s.board.insert(card, at: to); s.terminal = true
        }
        guard RecruitEffects.triggerEffects(step.kind, before: original, state: &s, context: context) else { return nil }
        if step.kind == .play || step.kind == .spell {
            RecruitMechanics.playedCard(before: original, state: &s, context: context)
        }
        // Generated copies can themselves complete a triple.
        guard RecruitEffects.triples(state: &s, context: context) else { return nil }
        s.steps.append(step)
        return s
    }

    /// Strategic units, not claimed win percentages. Future production is discounted by health.
    public static func value(_ s: RecruitState, request: AdvisorRequest, context: RecruitContext) -> RecruitValue {
        var v = RecruitValue()
        let health = s.input.playerBoard.player.hpLeft
        let horizon = health <= 5 ? 0.35 : health <= 15 ? 1.0 : 2.0
        for card in s.board {
            let e = card.entity
            let stats = sqrt(Double(max(0, e.attack)) * Double(max(1, e.health)))
            v.tempo += stats * (e.divineShield ? 1.55 : 1) * (e.windfury ? 1.12 : 1)
                + (e.reborn ? 3 : 0) + (e.venomous || e.poisonous ? 8 : 0)
            v.tempo += RecruitMechanics.combatValue(card, state: s, context: context)
            v.scaling += production(card, state: s, context: context) * horizon
        }
        for deity in s.input.playerBoard.player.secrets where deity.cardId == "BG_OldGod" {
            let attack = deity.tags?["4914"] ?? deity.scriptDataNum2
            let health = deity.tags?["4915"] ?? deity.scriptDataNum3
            v.tempo += sqrt(Double(max(0, attack)) * Double(max(0, health))) * 0.5
        }
        // Hand bodies are options, not on-board stats. Unspent gold does not carry over.
        v.economy = Double(s.gold) * 0.35 + Double(s.freeRolls) * 0.8
        // A triple gives an option at the next tier, never a guaranteed core card. Keep this
        // conservative and flag the unknown choice in the plan's limitations.
        if s.pendingDiscover > 0 || s.limitations.contains(where: { $0.hasPrefix("Triple reward") }) {
            v.economy += Double(min(6, s.tier + 1)) * 1.5 * min(1, horizon)
        }
        for card in s.hand { v.economy += card.isMinion ? 1.2 : 0.8 }
        let unlocked = max(0, s.tier - request.tier)
        let curveTier = request.preview.bgTurn < 5 ? 2 : request.preview.bgTurn < 7 ? 3 : request.preview.bgTurn < 9 ? 4 : 5
        v.economy += Double(unlocked) * (s.tier <= curveTier ? 7 : 3) * horizon
        let held = s.board + s.hand
        for build in request.builds ?? [] {
            let core = Set(held.map { context.base($0.cardID) }).intersection(build.core).count
            let support = Set(held.map { context.base($0.cardID) }).intersection(build.addons).count
            // Supporting cards have value when there is an engine; catalog membership alone is weak.
            v.synergy += build.share * Double(core * 3 + (core > 0 ? support * 2 : 0)) * horizon
        }
        if s.frozen, !request.shopFrozen {
            // Only pay for preserving a known, unaffordable engine card, not for the freeze itself.
            v.economy += s.shop.filter { ($0.cost ?? 3) > s.gold }.map { production($0, state: s, context: context) * horizon - 3 }.max().map { max(0, $0) } ?? 0
        }
        if s.steps.last?.kind == .roll {
            // Small option value, never a fabricated new board or guaranteed desired card.
            v.economy += s.gold >= 3 ? 1.5 : 0
        }
        v.economy += Double(s.unknownRewards) * 0.8
        return v
    }

    /// Production estimates describe a card's role and its inputs. They are deliberately separate
    /// from exact recruit effects and never used to fabricate a combat board.
    public static func production(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> Double {
        RecruitMechanics.production(card, state: state, context: context)
            + baseProduction(card, state: state, context: context)
    }

    private static func baseProduction(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> Double {
        let text = context.text(card.cardID).lowercased()
        // Battlecries have already been resolved by the transition. Counting their rewards
        // again every future turn would incorrectly protect disposable cycle minions.
        if text.hasPrefix("battlecry:") || text.hasPrefix("when you sell this") { return 0 }
        let gems = state.board.contains { context.text($0.cardID).lowercased().contains("blood gem") }
        let gemValue = Double(2 + (state.input.playerBoard.player.globalInfo["BloodGemAttackBonus"] ?? 0)
                                + (state.input.playerBoard.player.globalInfo["BloodGemHealthBonus"] ?? 0)).squareRoot()
        if text.contains("blood gems played from your hand") {
            let supply = state.hand.filter { $0.cardID == "BG20_GEM" }.count
                + state.board.filter { context.text($0.cardID).lowercased().contains("get") && context.text($0.cardID).lowercased().contains("blood gem") }.count * 2
            return Double(min(supply, 8)) * gemValue
        }
        if text.contains("plays a blood gem on all") || text.contains("plays 2 blood gems on all") {
            return Double(max(0, state.board.count - 1)) * gemValue * (card.golden ? 2 : 1)
        }
        if text.contains("blood gems give an extra"), gems { return gemValue * 4 }
        if text.contains("get"), text.contains("blood gem") { return gemValue * (card.golden ? 4 : 2) }
        if text.contains("end of your turn") {
            return (text.contains("all") || text.contains("your minions") ? Double(state.board.count) * 2 : 3)
                * (card.golden ? 2 : 1) * Double(RecruitEffects.endOfTurnRepeats(state, context: context))
        }
        if text.contains("get"), text.contains("gold") || text.contains("coin") { return 3 }
        if text.contains("sludge corrosion") { return Double(state.board.count) * (card.golden ? 1.2 : 0.6) }
        return 0
    }

    public static func search(_ request: AdvisorRequest, context: RecruitContext, budget: Budget = Budget(),
                              shouldContinue: () -> Bool = { true }) -> RecruitSearch {
        let initial = RecruitState(request: request, context: context)
        func plan(_ s: RecruitState) -> RecruitPlan {
            let projection = RecruitEffects.combatProjection(s, context: context)
            return RecruitPlan(state: s, projection: projection,
                               value: value(projection, request: request, context: context))
        }
        let baseline = plan(initial)
        var beam = [initial], all: [RecruitPlan] = [], expanded = 0
        var limitations = Set(baseline.projection.limitations + RecruitMechanics.limitations(initial, context: context))
        for card in request.board + request.hand + request.shop {
            if context.definitions[card.cardID] == nil { limitations.insert("Missing card definitions") }
            if card.isMinion, !request.board.contains(where: { $0.entity.entityId == card.entity.entityId }),
               !RecruitEffects.isSupported(RecruitEffects.battlecry(card, context: context)) {
                limitations.insert("Unmodelled play effect: \(name(card, context))")
            }
            if !card.isMinion, !RecruitEffects.isSupported(spellEffect(card, state: initial, context: context)) {
                limitations.insert("Unmodelled spell: \(name(card, context))")
            }
        }
        for kind in [RecruitStep.Kind.buy, .play, .sell, .spell] {
            if !RecruitEffects.triggersSupported(kind, state: initial, context: context) {
                limitations.insert("Unmodelled \(kind.rawValue) trigger on the board")
            }
        }
        for power in initial.input.playerBoard.player.heroPowers where !power.used && power.locked == 0 {
            if let cost = context.powerCosts[power.cardId], cost <= initial.gold,
               !RecruitEffects.isSupported(RecruitEffects.effect(context.text(power.cardId))) {
                // Passive combat powers need no recruit action and are already handled by the combat simulator.
                let text = context.text(power.cardId).lowercased()
                if !text.contains("passive") && !text.contains("combat") && !text.contains("start of") {
                    limitations.insert("Unmodelled hero power: \(context.definitions[power.cardId]?.name ?? power.cardId)")
                }
            }
        }
        for _ in 0..<max(0, budget.depth) {
            var next: [RecruitState] = []
            for s in beam {
                for step in actions(s, context: context, canFreeze: request.canFreeze) {
                    guard expanded < budget.expansions, shouldContinue() else { break }
                    expanded += 1
                    guard let result = applying(step, to: s, context: context) else { continue }
                    next.append(result)
                    // A buy is allowed to remain in hand for triples, but plans ending in an
                    // ordinary unplayed purchase are not promoted by hand-option value alone.
                    all.append(plan(result))
                }
                if expanded >= budget.expansions || !shouldContinue() { break }
            }
            next.sort {
                let a = value($0, request: request, context: context).total
                let b = value($1, request: request, context: context).total
                return a == b ? $0.steps.map(\.id).joined() < $1.steps.map(\.id).joined() : a > b
            }
            // Preserve first-action diversity so a good cycle can survive its temporary weak board.
            var perFirst: [String: Int] = [:]
            beam = next.filter { s in
                guard !s.terminal, let first = s.steps.first else { return false }
                perFirst[first.id, default: 0] += 1
                return perFirst[first.id]! <= 3
            }.prefix(max(1, budget.width)).map { $0 }
            if beam.isEmpty || expanded >= budget.expansions || !shouldContinue() { break }
        }
        var best: [String: RecruitPlan] = [:]
        for p in all {
            guard let first = p.state.steps.first else { continue }
            if let old = best[first.id], old.value.total >= p.value.total { continue }
            best[first.id] = p
        }
        let plans = best.values.sorted { a, b in a.value.total == b.value.total ? a.id < b.id : a.value.total > b.value.total }
        return RecruitSearch(baseline: baseline, plans: Array(plans.prefix(12)), limitations: limitations.sorted(), expanded: expanded)
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}
