/// The captured recruit attack is replacement -> Rally -> zero-damage attack ->
/// Fishbait Deathrattle. Other attack chains need their own verified transitions.
enum RecruitLurkingLionfish: RecruitCardEffect {
    static let normal = "BG36_201", golden = "BG36_201_G"
    static let cardIDs: Set<String> = [normal, golden]
    static let since = AdvisorPolicy.Feature.lionfishActivate.introduced
    static let generated = ["BG36_205", "BG36_205_G"]
    static let requiresObservedActivationCost = true

    static func activationRecognized(_ card: AdvisorCard, context: RecruitContext) -> Bool {
        recognized(card, context: context)
    }

    private static func recognized(_ card: AdvisorCard, context: RecruitContext) -> Bool {
        guard card.isMinion, context.definitions[card.cardID]?.type == "MINION",
              !RecruitCardEffects.activatesTwice(card, context) else { return false }
        switch (card.cardID, context.text(card.cardID)) {
        case (normal, "Activate (2): Choose a card in the Tavern. Replace it with a Fishbait for your left-most Beast to attack."),
             (golden, "Activate (2): Choose a card in the Tavern. Replace it with a Golden Fishbait for your left- most Beast to attack."):
            return true
        default: return false
        }
    }

    private static func token(_ card: AdvisorCard, context: RecruitContext) -> (id: String, health: Int, buff: Int)? {
        let isGolden = card.cardID == golden, id = isGolden ? "BG36_205_G" : "BG36_205"
        let health = isGolden ? 2 : 1, amount = isGolden ? 10 : 5
        guard let definition = context.definitions[id], definition.type == "MINION",
              definition.attack == 0, definition.health == health,
              (definition.races ?? []).contains("BEAST"), Set(definition.mechanics ?? []) == ["DEATHRATTLE"],
              context.text(id) == "This can't gain stats. Deathrattle: Give the minion that killed this +\(amount)/+\(amount)." else { return nil }
        return (id, health, amount)
    }

    private static func attacker(_ state: RecruitState, context: RecruitContext) -> Int? {
        for index in state.board.indices {
            guard let definition = context.definitions[state.board[index].cardID] else { return nil }
            let tribes = definition.races ?? []
            if tribes.contains("BEAST") || tribes.contains("ALL") { return index }
        }
        return nil
    }

    private static func rally(_ card: AdvisorCard, context: RecruitContext) -> (Int, Int)? {
        switch (card.cardID, context.text(card.cardID)) {
        case ("BG36_207", "Rally: Give your other minions +4/+1."): return (4, 1)
        case ("BG36_207_G", "Rally: Give your other minions +8/+2."): return (8, 2)
        default: return nil
        }
    }

    private static func attackListener(_ text: String, personal: Bool) -> Bool {
        let t = text.lowercased()
        let friendly = ["after a friendly", "whenever a friendly", "after another friendly", "whenever another friendly",
                        "after one of your", "whenever one of your", "after a minion", "whenever a minion"]
        if friendly.contains(where: { t.contains($0) }),
           t.contains("attack") || t.contains("kill") || t.contains("damage") || t.contains("dies") { return true }
        if t.contains("your rally") || t.contains("rally effects") || t.contains("fishbait") && !t.hasPrefix("activate") { return true }
        if personal, t.contains("rally:") || t.contains("this attacks") || t.contains("this minion attacks")
            || t.contains("this kills") || t.contains("this minion kills") || t.contains("this deals damage")
            || t.contains("can't attack") || t.contains("cannot attack") { return true }
        return false
    }

    static func reason(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> String? {
        guard token(card, context: context) != nil else { return "Fishbait token definition is missing or changed" }
        guard let index = attacker(state, context: context), let bait = token(card, context: context) else { return "leftmost Beast is unknown" }
        let attacking = state.board[index]
        if (context.definitions[attacking.cardID]?.mechanics ?? []).contains("BACON_RALLY"),
           rally(attacking, context: context) == nil { return "attack Rally definition is unmodelled" }
        guard attacking.entity.attack >= bait.health, attacking.entity.health > 0 else { return "attacker cannot make the verified one-hit kill" }
        guard !attacking.entity.venomous, !attacking.entity.poisonous, !attacking.entity.stealth, !attacking.entity.windfury else {
            return "attacker keyword transition is unmodelled"
        }
        for minion in state.board {
            guard context.definitions[minion.cardID]?.type == "MINION" else { return "attack observer definition is missing" }
            let personal = minion.entity.entityId == attacking.entity.entityId
            let text = context.text(minion.cardID)
            if attackListener(text, personal: personal), !(personal && rally(minion, context: context) != nil) {
                return "attack trigger on \(RecruitPlanner.name(minion, context)) is unmodelled"
            }
            for gift in RecruitMechanics.gifts(minion, context) {
                if gift.isEmpty || attackListener(gift, personal: personal) { return "attack Dark Gift is unmodelled" }
            }
        }
        for trinket in state.input.playerBoard.player.trinkets {
            let text = context.text(trinket.cardId), t = text.lowercased()
            if text.isEmpty || attackListener(text, personal: true) || t.contains("lionfish")
                || t.contains("attacks") || t.contains("attacked") || t.contains("rally") {
                return "attack trinket is unmodelled"
            }
        }
        for power in state.input.playerBoard.player.heroPowers {
            let text = context.text(power.cardId)
            if text.isEmpty || attackListener(text, personal: true) { return "attack hero power is unmodelled" }
        }
        return nil
    }

    static func activationLimitation(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> String? {
        guard recognized(card, context: context),
              RecruitCardEffects.availableActivation(card.entity.entityId, state: state, context: context, observedCost: true) != nil,
              !state.shop.isEmpty,
              let reason = reason(card, state: state, context: context) else { return nil }
        return "Lionfish attack unresolved: \(reason)"
    }

    static func activationActions(_ card: AdvisorCard, index: Int, state: RecruitState, context: RecruitContext) -> [RecruitStep]? {
        guard recognized(card, context: context) else { return nil }
        guard let available = RecruitCardEffects.availableActivation(card.entity.entityId, state: state, context: context, observedCost: true),
              reason(card, state: state, context: context) == nil else { return [] }
        return state.shop.enumerated().map { shopIndex, target in
            RecruitCardEffects.targetedActivation(card, index: index, cost: available.cost, target: target,
                                                  position: AdvisorTarget(.shop, shopIndex), context: context)
        }
    }

    static func activate(_ step: RecruitStep, source: AdvisorCard, state: inout RecruitState, context: RecruitContext) -> Bool? {
        guard recognized(source, context: context) else { return nil }
        guard let available = RecruitCardEffects.availableActivation(step.entityID, state: state, context: context, observedCost: true),
              reason(source, state: state, context: context) == nil,
              let shopIndex = state.shop.firstIndex(where: { $0.entity.entityId == step.targetID }),
              let attackerIndex = attacker(state, context: context), let bait = token(source, context: context),
              var replacement = RecruitEffects.token(bait.id, state: &state, context: context) else { return false }
        replacement.entity.entityId = state.shop[shopIndex].entity.entityId
        state.shop[shopIndex] = replacement
        let attacking = state.board[attackerIndex]
        if let stats = rally(attacking, context: context) {
            for index in state.board.indices where index != attackerIndex {
                RecruitEffects.buff(&state.board[index], attack: stats.0, health: stats.1)
            }
        }
        // Exact zero-Attack Fishbait deals no damage. The verified attack kills it;
        // its Deathrattle buffs that killer, then removes the replaced Tavern entity.
        RecruitEffects.buff(&state.board[attackerIndex], attack: bait.buff, health: bait.buff)
        state.shop.remove(at: shopIndex)
        RecruitCardEffects.spendActivation(available, entityID: step.entityID, state: &state)
        return true
    }
}
