import Foundation

/// Seasonal mechanics share the same state transitions as ordinary recruit actions. Printed
/// stats already include historical buffs; only new events apply enchantment buffs here.
enum RecruitMechanics {
    static func gifts(_ card: AdvisorCard, _ context: RecruitContext) -> [String] {
        card.entity.enchantments.filter { $0.cardId.hasPrefix("BG36_MidGameEffect_") }
            .map { context.text($0.cardId) }
    }

    static func playedCard(before: RecruitState, state: inout RecruitState, context: RecruitContext) {
        for card in before.board {
            guard let i = state.board.firstIndex(where: { $0.entity.entityId == card.entity.entityId }) else { continue }
            for text in gifts(card, context) {
                if let c = RecruitEffects.captures("Whenever you play a card, gain \\+([0-9]+)/\\+([0-9]+)\\.", text) {
                    RecruitEffects.buff(&state.board[i], attack: Int(c[0])!, health: Int(c[1])!)
                } else if let c = RecruitEffects.captures("Whenever you play a card, gain \\+([0-9]+) (Attack|Health)\\.", text) {
                    RecruitEffects.buff(&state.board[i], attack: c[1] == "Attack" ? Int(c[0])! : 0,
                                        health: c[1] == "Health" ? Int(c[0])! : 0)
                }
            }
        }
    }

    static func counterBuffs(_ event: String, state: inout RecruitState, context: RecruitContext) {
        let key = event == "Tavern spell you've cast" ? "TavernSpellsCastThisGame" : "BattlecriesTriggeredThisGame"
        state.input.playerBoard.player.globalInfo[key, default: 0] += 1
        for i in state.board.indices {
            for text in gifts(state.board[i], context) where text.contains(event) {
                if let c = RecruitEffects.captures("Has \\+([0-9]+)/\\+([0-9]+) for each .+", text) {
                    RecruitEffects.buff(&state.board[i], attack: Int(c[0])!, health: Int(c[1])!)
                }
            }
        }
    }

    static func combatValue(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> Double {
        let strength = sqrt(Double(max(0, card.entity.attack)) * Double(max(1, card.entity.health)))
        var bonus = 0.0
        for text in gifts(card, context) {
            switch text {
            case "Start of Combat: Triple this minion's stats.": bonus += 2 * strength
            case "Start of Combat: Double this minion's Attack.", "Start of Combat: Double this minion's Health.":
                bonus += (sqrt(2.0) - 1) * strength
            case "Reborn. Is Reborn with full stats and Bonus Keywords.": bonus += 0.7 * strength
            case "This minion's Divine Shield takes 3 hits to break.": bonus += strength
            case "Immune while attacking.": bonus += 0.35 * strength
            case "Deathrattle: Summon a Golem with this minion's stats.": bonus += 0.7 * strength
            case "Deathrattle: Give this minion's Attack to another friendly minion.",
                 "Deathrattle: Give this minion's max Health to another friendly minion.":
                if state.board.count > 1 { bonus += 0.35 * strength }
            case "Start of Combat: Gain the stats of your Deity.":
                if let deity = state.input.playerBoard.player.secrets.first(where: { $0.cardId == "BG_OldGod" }) {
                    let a = max(0, deity.tags?["4914"] ?? deity.scriptDataNum2)
                    let h = max(0, deity.tags?["4915"] ?? deity.scriptDataNum3)
                    bonus += sqrt(Double(card.entity.attack + a) * Double(max(1, card.entity.health + h))) - strength
                }
            default: break
            }
        }
        return bonus
    }

    static func activationBody(_ card: AdvisorCard, _ context: RecruitContext) -> String? {
        RecruitEffects.captures(".*Activate \\([0-9]+\\): (.+)", context.text(card.cardID))?.first
    }

    static func activationSupported(_ card: AdvisorCard, _ context: RecruitContext) -> Bool {
        guard let body = activationBody(card, context),
              !gifts(card, context).contains("This minion's Activate triggers twice.") else { return false }
        if body == "Discard a card to get a random Tavern spell." { return true }
        if body.hasPrefix("Discard a card to ") {
            let effect = String(body.dropFirst("Discard a card to ".count))
            return RecruitEffects.isSupported(RecruitEffects.effect(effect.prefix(1).uppercased() + effect.dropFirst()))
        }
        return false
    }

    static func activate(_ step: RecruitStep, state: inout RecruitState, context: RecruitContext) -> Bool {
        guard let i = state.board.firstIndex(where: { $0.entity.entityId == step.entityID }),
              let availability = context.activations?[step.entityID], availability.ready,
              !state.usedActivations.contains(step.entityID), availability.cost <= state.gold,
              let body = activationBody(state.board[i], context), activationSupported(state.board[i], context),
              let h = state.hand.firstIndex(where: { $0.entity.entityId == step.targetID }),
              !state.hand[h].entity.locked else { return false }
        let discarded = state.hand.remove(at: h)
        state.gold -= availability.cost; state.usedActivations.insert(step.entityID)
        guard discardEffects(discarded, state: &state, context: context) else { return false }
        if body == "Discard a card to get a random Tavern spell." {
            if state.hand.count + state.unknownRewards < AdvisorRequest.handLimit { state.unknownRewards += 1 }
            state.terminal = true
            state.limitations.append("Random Tavern spell: reveal it and reassess")
        } else {
            let text = String(body.dropFirst("Discard a card to ".count))
            guard RecruitEffects.apply(RecruitEffects.effect(text.prefix(1).uppercased() + text.dropFirst()),
                                       target: nil, state: &state, context: context) else { return false }
        }

        return true
    }

    /// Shared by activations and linked hero-power rewards.
    static func discardEffects(_ discarded: AdvisorCard, state: inout RecruitState, context: RecruitContext) -> Bool {
        // Unknown discard text must not silently vanish with the card.
        let discardText = context.text(discarded.cardID)
        let sludge = discardText == "Give your minions +1/+1. If you discard this, cast it twice."
        if discardText.lowercased().contains("discard"), !sludge { return false }
        state.input.playerBoard.player.globalInfo["CardsDiscardedThisGame", default: 0] += 1
        for trinket in state.input.playerBoard.player.trinkets {
            let text = context.text(trinket.cardId)
            if text == "Get a Sludge Corrosion. After you discard a card, get a Sludge Corrosion." {
                // Discard triggers resolve before the activator reward (confirmed in the match log).
                if state.hand.count + state.unknownRewards < AdvisorRequest.handLimit {
                    guard RecruitEffects.apply(.token("BG36_301t", 1, toHand: true), target: nil, state: &state, context: context) else { return false }
                }
            } else if text.lowercased().contains("discard") { return false }
        }
        if sludge {
            guard RecruitEffects.triggersSupported(.spell, state: state, context: context) else { return false }
            for _ in 0..<2 {
                let before = state
                guard RecruitEffects.apply(.buff(1, 1, all: true), target: nil, state: &state, context: context),
                      RecruitEffects.triggerEffects(.spell, before: before, state: &state, context: context) else { return false }
                counterBuffs("Tavern spell you've cast", state: &state, context: context)
                state.input.playerBoard.player.globalInfo["SpellsCastThisGame", default: 0] += 1
            }
        }
        for j in state.board.indices {
            for text in gifts(state.board[j], context) {
                if let c = RecruitEffects.captures("Has \\+([0-9]+)/\\+([0-9]+) for each card you've discarded this game\\. \\(0\\)", text) {
                    RecruitEffects.buff(&state.board[j], attack: Int(c[0])!, health: Int(c[1])!)
                }
            }
        }
        return true
    }

    static func trinketSupported(_ id: String, context: RecruitContext) -> Bool {
        let text = context.text(id)
        if (id == "BG36_MagicItem_302" || id == "BG36_MagicItem_302t") && text.hasPrefix("At the end of your turn, give your minions +") { return true }
        if text == "Your end of turn effects trigger an extra time." { return true }
        if text == "When you buy a Greater Trinket, this transforms into a copy of it."
            || text == "Get a Sludge Corrosion. After you discard a card, get a Sludge Corrosion." { return true }
        // Combat effects remain attached to the input; the pinned combat simulator resolves them.
        return text.hasPrefix("Start of Combat:") && !text.contains("At the end")
    }

    static func limitations(_ state: RecruitState, context: RecruitContext, projectionOnly: Bool = false) -> [String] {
        var result: [String] = []
        for t in state.input.playerBoard.player.trinkets where !trinketSupported(t.cardId, context: context) {
            if projectionOnly, state.steps.allSatisfy({ $0.kind == .move }),
               !context.text(t.cardId).isEmpty, !context.text(t.cardId).lowercased().contains("end of") { continue }
            result.append("Unmodelled trinket: \(context.definitions[t.cardId]?.name ?? t.cardId)")
        }
        for card in state.board {
            for enchantment in card.entity.enchantments where enchantment.cardId.hasPrefix("BG36_MidGameEffect_") {
                let text = context.text(enchantment.cardId)
                // Combat-only/stat attachments are already in the simulator input. Recruit effects
                // require an explicit handler; unsupported ones must affect confidence.
                if text.isEmpty || text.contains("At the end") || text.contains("also trigger at start") || text.hasPrefix("In ")
                    || (text.contains("Whenever you") && !text.hasPrefix("Whenever you play a card, gain +")) {
                    result.append("Unmodelled Dark Gift: \(context.definitions[enchantment.cardId]?.name ?? enchantment.cardId)")
                }
            }
            if !projectionOnly, context.text(card.cardID).contains("Activate ("), !activationSupported(card, context) {
                result.append("Unmodelled Activate: \(context.definitions[card.cardID]?.name ?? card.cardID)")
            }
        }
        return Array(Set(result)).sorted()
    }

    /// Estimated future resources, not fabricated combat results. Deity stats/progress and
    /// attached gifts travel intact into the simulator for actual combat checks.
    static func production(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> Double {
        let text = context.text(card.cardID)
        var value = 0.0
        let deaths = card.entity.reborn ? 2.0 : 1.0
        if (context.definitions[card.cardID]?.races ?? []).contains("ABERRATION"),
           let deity = state.input.playerBoard.player.secrets.first(where: { $0.cardId == "BG_OldGod" }) {
            let strength = sqrt(Double(max(0, deity.tags?["4914"] ?? deity.scriptDataNum2))
                * Double(max(0, deity.tags?["4915"] ?? deity.scriptDataNum3)))
            // Remaining deaths determine how close this board is to summoning the Deity.
            value += min(12, strength / Double(max(1, deity.scriptDataNum1))) * deaths * 0.25
        }
        if let c = RecruitEffects.captures(".*Deathrattle: Give your Deity \\+([0-9]+)/\\+([0-9]+)\\..*", text),
           state.input.playerBoard.player.secrets.contains(where: { $0.cardId == "BG_OldGod" }) {
            value += Double(Int(c[0])! + Int(c[1])!) * deaths * 0.5
        }
        if text.contains("Deathrattle:"), text.contains("Fodder") { value += 2 * deaths }
        if text.contains("Deathrattle:"), text.contains("Get") { value += deaths }
        if text.contains("Activate ("), text.contains("Discard a card") {
            let portraits = state.input.playerBoard.player.trinkets.filter {
                context.text($0.cardId) == "Get a Sludge Corrosion. After you discard a card, get a Sludge Corrosion."
            }.count
            let supply = state.hand.contains { context.text($0.cardID).contains("If you discard this, cast it twice.") }
            value += Double(portraits) * Double(state.board.count) * 0.5 + (supply ? 2 : 0)
        }
        for gift in gifts(card, context) {
            if gift.hasPrefix("Whenever you play a card, gain") { value += 3 }
            if gift.hasPrefix("Has +"), gift.contains("discarded"), state.board.contains(where: {
                context.text($0.cardID).contains("Discard a card")
            }) { value += 3 }
            if gift.contains("Deathrattle: Get") || gift.contains("Rally: Get") { value += 2 * deaths }
            if gift.contains("keeps"), gift.contains("stats gained in combat") { value += 3 }
        }
        return value
    }
}
