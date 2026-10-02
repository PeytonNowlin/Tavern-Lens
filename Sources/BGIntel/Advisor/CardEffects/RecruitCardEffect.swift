/// Everything the recruit planner knows about one card beyond the generic text grammar in
/// `RecruitEffects`. An entry owns its card IDs, the policy version it entered at, and every
/// hook it answers; a new card is one entry plus one line in `RecruitCardEffects.all`.
///
/// Card-keyed hooks are asked only about the entry's own `cardIDs`. Listener hooks are asked of
/// every active entry. Nil from a card-keyed hook means "not handled here": the caller falls
/// back to its generic rules, exactly as when the entry is inactive.
protocol RecruitCardEffect: Sendable {
    /// Normal and golden IDs this entry owns.
    static var cardIDs: Set<String> { get }
    /// First policy version that consults this entry. Earlier policies behave as if it were absent.
    static var since: Int { get }
    /// Definitions the search may create from these cards. Captured with every request,
    /// whatever its policy, because the snapshot is taken before a policy is selected.
    static var generated: [String] { get }
    /// The Activate price must come from live tag 4090, not printed text.
    static var requiresObservedActivationCost: Bool { get }

    // Activate (card-keyed)
    static func activationRecognized(_ card: AdvisorCard, context: RecruitContext) -> Bool
    static func activationLimitation(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> String?
    /// An empty list means this recognized effect has no safe legal target right now.
    static func activationActions(_ card: AdvisorCard, index: Int, state: RecruitState, context: RecruitContext) -> [RecruitStep]?
    static func activate(_ step: RecruitStep, source: AdvisorCard, state: inout RecruitState, context: RecruitContext) -> Bool?

    // Trinkets (card-keyed)
    static func trinketSupported(_ id: String, context: RecruitContext) -> Bool?

    // Spells and Battlecries (card-keyed)
    static func spellEffect(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> RecruitEffects.Effect?
    static func spellTargetAllowed(_ card: AdvisorCard, target: Int?, state: RecruitState, context: RecruitContext) -> Bool?
    static func battlecry(_ card: AdvisorCard, context: RecruitContext) -> RecruitEffects.Effect?

    // Listeners (every active entry). False rejects the transition.
    static func afterBuy(_ bought: AdvisorCard, state: inout RecruitState, context: RecruitContext) -> Bool
    static func afterSell(_ sold: AdvisorCard, state: inout RecruitState, context: RecruitContext)
    static func afterPlay(before: RecruitState, state: inout RecruitState, context: RecruitContext) -> Bool
    static func afterPlayerSpell(_ step: RecruitStep, before: RecruitState, state: inout RecruitState, context: RecruitContext) -> Bool
    static func canTriple(_ cards: [AdvisorCard], state: RecruitState, context: RecruitContext) -> Bool
    static func afterTriple(_ cardID: String, consumed: Set<Int>, golden: AdvisorCard, state: inout RecruitState, context: RecruitContext)
    static func beforeCombatProjection(_ state: inout RecruitState, context: RecruitContext)
}

extension RecruitCardEffect {
    static var generated: [String] { [] }
    static var requiresObservedActivationCost: Bool { false }

    static func activationRecognized(_ card: AdvisorCard, context: RecruitContext) -> Bool { false }
    static func activationLimitation(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> String? { nil }
    static func activationActions(_ card: AdvisorCard, index: Int, state: RecruitState, context: RecruitContext) -> [RecruitStep]? { nil }
    static func activate(_ step: RecruitStep, source: AdvisorCard, state: inout RecruitState, context: RecruitContext) -> Bool? { nil }

    static func trinketSupported(_ id: String, context: RecruitContext) -> Bool? { nil }

    static func spellEffect(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> RecruitEffects.Effect? { nil }
    static func spellTargetAllowed(_ card: AdvisorCard, target: Int?, state: RecruitState, context: RecruitContext) -> Bool? { nil }
    static func battlecry(_ card: AdvisorCard, context: RecruitContext) -> RecruitEffects.Effect? { nil }

    static func afterBuy(_ bought: AdvisorCard, state: inout RecruitState, context: RecruitContext) -> Bool { true }
    static func afterSell(_ sold: AdvisorCard, state: inout RecruitState, context: RecruitContext) {}
    static func afterPlay(before: RecruitState, state: inout RecruitState, context: RecruitContext) -> Bool { true }
    static func afterPlayerSpell(_ step: RecruitStep, before: RecruitState, state: inout RecruitState, context: RecruitContext) -> Bool { true }
    static func canTriple(_ cards: [AdvisorCard], state: RecruitState, context: RecruitContext) -> Bool { true }
    static func afterTriple(_ cardID: String, consumed: Set<Int>, golden: AdvisorCard, state: inout RecruitState, context: RecruitContext) {}
    static func beforeCombatProjection(_ state: inout RecruitState, context: RecruitContext) {}
}

/// The card-effect table. The planner, mechanics and effects consult it instead of calling
/// individual card files.
enum RecruitCardEffects {
    /// Precedence order. Card IDs never overlap (checked by tests).
    static let all: [any RecruitCardEffect.Type] = [
        // Activate
        RecruitSuspiciousPrisonguard.self, RecruitDecoyConjurer.self, RecruitFruitVendor.self,
        RecruitLivingPrison.self, RecruitLurkingLionfish.self,
        // Trinkets
        RecruitOrnateClock.self, RecruitNomiSticker.self, RecruitLovelyLocket.self, RecruitDeathlyPhylactery.self,
        RecruitManipulatorPortrait.self, RecruitPocketCyclone.self, RecruitFaerieDragonScale.self,
        RecruitBeetleBand.self, RecruitRockinMusicBox.self, RecruitGoldMallet.self,
        // Spells and Battlecries
        RecruitFortify.self, RecruitArcaneAbsorption.self, RecruitLeylineSurfacer.self,
    ]

    private static let byCardID: [String: any RecruitCardEffect.Type] = {
        var result: [String: any RecruitCardEffect.Type] = [:]
        for entry in all { for id in entry.cardIDs { result[id] = entry } }
        return result
    }()

    static func isActive(_ entry: any RecruitCardEffect.Type, _ context: RecruitContext) -> Bool {
        context.policy >= AdvisorPolicy(version: entry.since)
    }

    private static func entry(_ id: String, _ context: RecruitContext) -> (any RecruitCardEffect.Type)? {
        guard let entry = byCardID[id], isActive(entry, context) else { return nil }
        return entry
    }

    private static func active(_ context: RecruitContext) -> [any RecruitCardEffect.Type] {
        all.filter { isActive($0, context) }
    }

    // MARK: Request capture (policy-independent)

    static func generated(for observed: [AdvisorCard]) -> [String] {
        let ids = Set(observed.map(\.cardID))
        return all.filter { !$0.cardIDs.isDisjoint(with: ids) }.flatMap { $0.generated }
    }

    static func requiresObservedActivationCost(_ id: String) -> Bool {
        byCardID[id]?.requiresObservedActivationCost ?? false
    }

    // MARK: Activate

    static func activationRecognized(_ card: AdvisorCard, context: RecruitContext) -> Bool {
        entry(card.cardID, context)?.activationRecognized(card, context: context) ?? false
    }

    static func activationLimitation(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> String? {
        entry(card.cardID, context)?.activationLimitation(card, state: state, context: context)
    }

    /// Nil leaves legacy discard activations to their original handler.
    static func activationActions(_ card: AdvisorCard, index: Int, state: RecruitState, context: RecruitContext) -> [RecruitStep]? {
        entry(card.cardID, context)?.activationActions(card, index: index, state: state, context: context)
    }

    static func activate(_ step: RecruitStep, state: inout RecruitState, context: RecruitContext) -> Bool? {
        guard let source = state.board.first(where: { $0.entity.entityId == step.entityID }),
              let entry = entry(source.cardID, context) else { return nil }
        return entry.activate(step, source: source, state: &state, context: context)
    }

    // MARK: Trinkets

    static func trinketSupported(_ id: String, context: RecruitContext) -> Bool? {
        entry(id, context)?.trinketSupported(id, context: context)
    }

    // MARK: Spells and Battlecries

    static func spellEffect(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> RecruitEffects.Effect? {
        entry(card.cardID, context)?.spellEffect(card, state: state, context: context)
    }

    static func spellTargetAllowed(_ card: AdvisorCard, target: Int?, state: RecruitState, context: RecruitContext) -> Bool {
        entry(card.cardID, context)?.spellTargetAllowed(card, target: target, state: state, context: context) ?? true
    }

    static func battlecry(_ card: AdvisorCard, context: RecruitContext) -> RecruitEffects.Effect? {
        entry(card.cardID, context)?.battlecry(card, context: context)
    }

    // MARK: Listeners

    static func afterBuy(_ bought: AdvisorCard, state: inout RecruitState, context: RecruitContext) -> Bool {
        for entry in active(context) {
            guard entry.afterBuy(bought, state: &state, context: context) else { return false }
        }
        return true
    }

    static func afterSell(_ sold: AdvisorCard, state: inout RecruitState, context: RecruitContext) {
        for entry in active(context) { entry.afterSell(sold, state: &state, context: context) }
    }

    static func afterPlay(before: RecruitState, state: inout RecruitState, context: RecruitContext) -> Bool {
        for entry in active(context) {
            guard entry.afterPlay(before: before, state: &state, context: context) else { return false }
        }
        return true
    }

    static func afterPlayerSpell(_ step: RecruitStep, before: RecruitState, state: inout RecruitState, context: RecruitContext) -> Bool {
        for entry in active(context) {
            guard entry.afterPlayerSpell(step, before: before, state: &state, context: context) else { return false }
        }
        return true
    }

    static func canTriple(_ cards: [AdvisorCard], state: RecruitState, context: RecruitContext) -> Bool {
        active(context).allSatisfy { $0.canTriple(cards, state: state, context: context) }
    }

    static func afterTriple(_ cardID: String, consumed: Set<Int>, golden: AdvisorCard, state: inout RecruitState, context: RecruitContext) {
        for entry in active(context) {
            entry.afterTriple(cardID, consumed: consumed, golden: golden, state: &state, context: context)
        }
    }

    static func beforeCombatProjection(_ state: inout RecruitState, context: RecruitContext) {
        for entry in active(context) { entry.beforeCombatProjection(&state, context: context) }
    }
}

// MARK: Shared Activate rules

extension RecruitCardEffects {
    /// Ready, affordable and unused this plan. `observedCost` also requires a live price.
    static func availableActivation(_ entityID: Int, state: RecruitState, context: RecruitContext,
                                    observedCost: Bool = false) -> RecruitContext.Activation? {
        guard let available = context.activations?[entityID], available.ready,
              !observedCost || available.costObserved != false,
              available.cost >= 0, available.cost <= state.gold,
              !state.usedActivations.contains(entityID) else { return nil }
        return available
    }

    static func spendActivation(_ available: RecruitContext.Activation, entityID: Int, state: inout RecruitState) {
        state.gold -= available.cost
        state.input.playerBoard.player.globalInfo["GoldSpentThisGame", default: 0] += available.cost
        state.usedActivations.insert(entityID)
    }

    static func untargetedActivation(_ card: AdvisorCard, index: Int, cost: Int, context: RecruitContext) -> RecruitStep {
        let action = AdvisorAction.activateUntargeted(board: index, cardID: card.cardID, cost: cost)
        return RecruitStep(kind: .activate, entityID: card.entity.entityId, action: action,
            title: action.title { context.definitions[$0]?.name ?? $0 })
    }

    static func targetedActivation(_ card: AdvisorCard, index: Int, cost: Int, target: AdvisorCard,
                                   position: AdvisorTarget, context: RecruitContext) -> RecruitStep {
        let action = AdvisorAction.activateMinion(board: index, cardID: card.cardID, cost: cost,
            target: position, targetCardID: target.cardID)
        return RecruitStep(kind: .activate, entityID: card.entity.entityId, targetID: target.entity.entityId,
            action: action, title: action.title { context.definitions[$0]?.name ?? $0 })
    }

    /// Effects that copy an Activate are not modelled; such cards stay unrecognized.
    static func activatesTwice(_ card: AdvisorCard, _ context: RecruitContext) -> Bool {
        RecruitMechanics.gifts(card, context).contains("This minion's Activate triggers twice.")
    }
}
