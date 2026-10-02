import Foundation

/// Version-six recruit coverage from captured discard games. Observed stats already contain
/// past triggers; only a new discard, board entry, or the upcoming end of turn changes them.
enum RecruitDiscardEffects {
    private static let hammer = "BG36_MagicItem_403"
    private static let hammerAura = "BG36_MagicItem_403e"
    private static let counter = "CardsDiscardedThisGame"
    private static let affinity = "BG36_MidGameEffect_000t82e"
    private static let affinityText = "At the end of every 2 turns, get a random minion of this type. (2 turns left!)2At the end of every 2 turns, get a random minion of this type. (End of this turn!)"

    static func enabled(_ context: RecruitContext) -> Bool { context.policy.has(.discardEffects) }

    static func supportsHammer(_ id: String, context: RecruitContext) -> Bool {
        enabled(context) && id == hammer && context.text(id)
            == "Your minions have +1 Attack. (Improved by each card you've discarded this game!)"
    }

    private static func discardCount(_ state: RecruitState) -> Int? {
        guard let count = state.input.playerBoard.player.globalInfo[counter], count >= 0,
              count < Int.max / 16 else { return nil }
        return count
    }

    private static func hammerIndices(_ state: RecruitState) -> [Int] {
        state.input.playerBoard.player.trinkets.indices.filter {
            let id = state.input.playerBoard.player.trinkets[$0].cardId
            return id == hammer || id == "BG36_MagicItem_403t"
        }
    }

    private static func hammerConfiguration(_ state: RecruitState, context: RecruitContext) -> (Int, Int)? {
        let indices = hammerIndices(state)
        guard indices.count == 1, let index = indices.first, let count = discardCount(state) else { return nil }
        let trinket = state.input.playerBoard.player.trinkets[index]
        guard supportsHammer(trinket.cardId, context: context), trinket.scriptDataNum1 == count + 1,
              trinket.scriptDataNum2 == 0 else { return nil }
        return (index, trinket.scriptDataNum1)
    }

    /// Use on entering the board, before the new body's battlecry or linked discard resolves.
    /// Existing attachments describe the portion already present in displayed Attack.
    static func synchronizeHammer(card: inout AdvisorCard, state: RecruitState, context: RecruitContext) -> Bool {
        guard enabled(context), card.isMinion else { return true }
        let attachments = card.entity.enchantments.indices.filter { card.entity.enchantments[$0].cardId == hammerAura }
        guard let (index, amount) = hammerConfiguration(state, context: context) else {
            return hammerIndices(state).isEmpty && attachments.isEmpty
        }
        guard attachments.count <= 1 else { return false }
        if let attachment = attachments.first {
            guard let old = card.entity.enchantments[attachment].tagScriptDataNum1, old >= 0, old <= amount,
                  (card.entity.enchantments[attachment].tagScriptDataNum2 ?? 0) == 0 else { return false }
            card.entity.attack += amount - old
            card.entity.enchantments[attachment].tagScriptDataNum1 = amount
        } else {
            card.entity.attack += amount
            card.entity.enchantments.append(BattleEnchantment(cardId: hammerAura,
                originEntityId: state.input.playerBoard.player.trinkets[index].entityId,
                tagScriptDataNum1: amount, tagScriptDataNum2: 0))
        }
        return true
    }

    /// An aura is not a permanent triple buff. Also use before replacing intrinsic stats.
    static func stripHammer(card: inout AdvisorCard, context: RecruitContext) {
        guard enabled(context) else { return }
        for enchantment in card.entity.enchantments where enchantment.cardId == hammerAura {
            card.entity.attack = max(0, card.entity.attack - max(0, enchantment.tagScriptDataNum1 ?? 0))
        }
        card.entity.enchantments.removeAll { $0.cardId == hammerAura }
    }

    static func hammerValidation(_ state: RecruitState, context: RecruitContext) -> [String] {
        guard enabled(context) else { return [] }
        let indices = hammerIndices(state)
        guard !indices.isEmpty else {
            return (state.board + state.hand).contains { $0.entity.enchantments.contains { $0.cardId == hammerAura } }
                ? ["Hammer of Twilight aura has no observed trinket"] : []
        }
        guard let (_, amount) = hammerConfiguration(state, context: context) else {
            return ["Hammer of Twilight discard count or aura is not resolved"]
        }
        for card in state.board {
            let attachments = card.entity.enchantments.filter { $0.cardId == hammerAura }
            guard attachments.count == 1, attachments[0].tagScriptDataNum1 == amount,
                  (attachments[0].tagScriptDataNum2 ?? 0) == 0 else {
                return ["Hammer of Twilight board aura is not resolved"]
            }
        }
        if state.hand.contains(where: { $0.entity.enchantments.contains { $0.cardId == hammerAura } }) {
            return ["Hammer of Twilight hand aura is not resolved"]
        }
        return []
    }

    /// The caller performs the card's own discard effect and other trinket rewards separately.
    static func discarded(state: inout RecruitState, context: RecruitContext) -> Bool {
        guard enabled(context) else { return true }
        let needsObservedCount = !hammerIndices(state).isEmpty || (state.board + state.hand + state.shop).contains(where: isFleshling)
        let count = discardCount(state) ?? (state.input.playerBoard.player.globalInfo[counter] == nil && !needsObservedCount ? 0 : nil)
        guard let count, hammerValidation(state, context: context).isEmpty else { return false }
        let configuration = hammerConfiguration(state, context: context)
        state.input.playerBoard.player.globalInfo[counter] = count + 1
        if let (index, _) = configuration {
            state.input.playerBoard.player.trinkets[index].scriptDataNum1 += 1
            for i in state.board.indices {
                var card = state.board[i]
                guard synchronizeHammer(card: &card, state: state, context: context) else { return false }
                state.board[i] = card
            }
        }
        for i in state.board.indices {
            if let amount = fleshlingAmount(state.board[i], state: state, context: context) {
                state.board[i].entity.scriptDataNum1 = amount; state.board[i].entity.scriptDataNum2 = amount
            } else if isFleshling(state.board[i]) { return false }
        }
        for i in state.hand.indices {
            if let amount = fleshlingAmount(state.hand[i], state: state, context: context) {
                state.hand[i].entity.scriptDataNum1 = amount; state.hand[i].entity.scriptDataNum2 = amount
            }
        }
        return true
    }

    private static func isFleshling(_ card: AdvisorCard) -> Bool {
        card.cardID == "BG36_114" || card.cardID == "BG36_114_G"
    }

    private static func fleshlingAmount(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> Int? {
        guard isFleshling(card), let count = discardCount(state) else { return nil }
        let base = card.cardID == "BG36_114_G" ? 4 : 2
        guard context.text(card.cardID) == "At the end of your turn, give your left-most minion +\(base)/+\(base). (Improved by each card you've discarded this game!)" else { return nil }
        // Captured script values are 12 at five discards (normal) and 52 at twelve
        // (golden). The pinned simulator's base + count implementation is stale here.
        return base * (count + 1)
    }

    /// nil means another card; false keeps a known but unsupported Fleshling uncertain.
    static func projectFleshling(_ card: AdvisorCard, state: inout RecruitState, context: RecruitContext) -> Bool? {
        guard enabled(context), isFleshling(card) else { return nil }
        guard let amount = fleshlingAmount(card, state: state, context: context) else { return false }
        guard let target = state.board.firstIndex(where: { $0.entity.health > 0 }) else { return true }
        let repeats = RecruitEffects.endOfTurnRepeats(state, context: context)
        let (buff, overflow) = amount.multipliedReportingOverflow(by: repeats)
        guard !overflow else { return false }
        RecruitEffects.buff(&state.board[target], attack: buff, health: buff)
        return true
    }

    /// Current production per future turn, without assuming any future discards. Time
    /// Turning supplies a separate start-of-turn trigger only in this strategic estimate.
    static func fleshlingProduction(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> Double? {
        guard enabled(context), let amount = fleshlingAmount(card, state: state, context: context) else { return nil }
        let startsTurn = card.entity.enchantments.contains {
            $0.cardId == "BG36_MidGameEffect_000t21e"
                && context.text($0.cardId) == "This minion's end of turn effects also trigger at start of turn."
        }
        return Double(amount) * Double(RecruitEffects.endOfTurnRepeats(state, context: context)) * (startsTurn ? 2 : 1)
    }

    static func supportsGift(_ enchantment: BattleEnchantment, state: RecruitState, context: RecruitContext) -> Bool? {
        guard enabled(context) else { return nil }
        let owner = state.board.first { $0.entity.enchantments.contains(enchantment) }
        switch enchantment.cardId {
        case "BG36_MidGameEffect_000t21e":
            // The start-of-turn trigger is already observed. The owner's pending EOT
            // must still reach a projection handler; prefixed or unknown text stays uncertain.
            guard context.text(enchantment.cardId) == "This minion's end of turn effects also trigger at start of turn.",
                  let owner else { return false }
            return isFleshling(owner) || context.text(owner.cardID).hasPrefix("At the end of your turn, ")
        case affinity:
            guard context.text(enchantment.cardId) == affinityText else { return false }
            if enchantment.tagScriptDataNum1 == 2, let owner,
               !owner.entity.enchantments.contains(where: { $0.cardId == "BG36_MidGameEffect_000t21e" }) {
                // Captured turns nine and eleven decrement 2 to 1 once, even with
                // Drakkari. No hand reward is due until the following end of turn.
                return true
            }
            return affinityHasNoCombatDependency(state, context: context)
        default: return nil
        }
    }

    private static func affinityHasNoCombatDependency(_ state: RecruitState, context: RecruitContext) -> Bool {
        // Even without a hand-reading combat card, an unknown reward can complete a
        // triple and pull a pair off the board. Do not invent that reward or its outcome.
        let held = state.board + state.hand
        let groups = Dictionary(grouping: held.filter { $0.isMinion && !$0.golden }, by: \.cardID)
        if groups.values.contains(where: { cards in
            cards.count >= 2 && cards.contains { card in state.board.contains { $0.entity.entityId == card.entity.entityId } }
        }) { return false }
        let player = state.input.playerBoard.player
        var ids = state.board.map(\.cardID) + state.board.flatMap { $0.entity.enchantments.map(\.cardId) }
        ids += player.heroPowers.map(\.cardId) + player.trinkets.map(\.cardId) + player.secrets.map(\.cardId)
        ids += player.questRewards + player.questEntities.map(\.CardId) + player.questRewardEntities.map(\.CardId)
        for id in Set(ids) where id != affinity {
            guard context.definitions[id] != nil else { return false }
            let text = context.text(id).lowercased()
            if text.contains("hand") || text.contains("holding") || text.contains("draw")
                || text.contains("after you get") || text.contains("whenever you get")
                || text.contains("after you add") || text.contains("whenever you add") { return false }
        }
        return true
    }
}
