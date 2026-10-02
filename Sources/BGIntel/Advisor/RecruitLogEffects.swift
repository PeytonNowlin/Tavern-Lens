import Foundation

/// Exact definitions from the recorded games. Combat effects stay in the pinned simulator;
/// only an observed pending recruit increment is applied to the projected board here.
enum RecruitLogEffects {
    static func enabled(_ context: RecruitContext) -> Bool { (context.evaluationVersion ?? 0) >= 5 }

    static func supportsTrinket(_ id: String, context: RecruitContext) -> Bool? {
        guard enabled(context) else { return nil }
        switch id {
        case RecruitSpellCopies.locketID:
            // Targeted player casts are resolved or limited per action by the copy handler.
            return RecruitSpellCopies.supportsLocket(id, context: context)
        case "BG30_MagicItem_700":
            // The simulator consumes tags[32], not scriptDataNum1. Older recordings lack
            // that observation; never assume their first Deathrattle is still available.
            return (context.evaluationVersion ?? 0) >= 7
                && context.text(id) == "Discover a Deathrattle minion. Your first Deathrattle each combat triggers an extra time."
                && context.input.playerBoard.player.trinkets.filter { $0.cardId == id }.allSatisfy {
                    $0.tags?["32"] == 0 || $0.tags?["32"] == 1
                }
        case "BG30_MagicItem_876":
            // Its one-time reward is already observed in hand. This does not model the
            // separate Faceless Manipulator copy Battlecry or grant another copy.
            return (context.evaluationVersion ?? 0) >= 7 && context.text(id) == "Get a Faceless Manipulator."
        case "BG32_MagicItem_363":
            // faerie-dragon-scale.js owns shield grants and the remaining-use counter.
            return context.text(id) == "Whenever a friendly Dragon attacks, give it Divine Shield. (3 times per combat.)"
        case "BG32_MagicItem_860t":
            // beetle-band.js owns avenge, summon count, Taunt and the global Beetle buffs.
            return context.text(id) == "Avenge (7): Summon two 2/2 Beetles. Give them Taunt."
        case "BG30_MagicItem_430":
            // This turn's random reward is already observed in hand. The next arrives after
            // combat; never invent a card or resolve another reward in this projection.
            return context.text(id) == "Get a random Battlecry minion. At the start of each turn, get another."
        default: return nil
        }
    }

    static func supportsGift(_ enchantment: BattleEnchantment, context: RecruitContext) -> Bool? {
        guard enabled(context) else { return nil }
        switch enchantment.cardId {
        case "BG36_MidGameEffect_000t51e": return growth(enchantment, context: context) != nil
        case "BG36_MidGameEffect_000t51e2": return context.text(enchantment.cardId) == "+0/+0."
        default: return nil
        }
    }

    private static func growth(_ enchantment: BattleEnchantment, context: RecruitContext) -> (Int, Int)? {
        guard enchantment.cardId == "BG36_MidGameEffect_000t51e",
              context.text(enchantment.cardId) == "At the end of your turn, gain +0/+0.",
              let attack = enchantment.tagScriptDataNum1, let health = enchantment.tagScriptDataNum2,
              attack >= 0, health >= 0 else { return nil }
        return (attack, health)
    }

    static func projectEndOfTurn(_ card: AdvisorCard, state: inout RecruitState, context: RecruitContext) {
        guard enabled(context), let index = state.board.firstIndex(where: { $0.entity.entityId == card.entity.entityId }) else { return }
        for enchantment in card.entity.enchantments {
            guard let amount = growth(enchantment, context: context) else { continue }
            // t51e2 is historical growth, already present in observed stats. t51e is the
            // pending increment; keep the attachments intact for simulator-owned combat.
            for _ in 0..<RecruitEffects.endOfTurnRepeats(state, context: context) {
                RecruitEffects.buff(&state.board[index], attack: amount.0, health: amount.1)
            }
        }
    }
}
