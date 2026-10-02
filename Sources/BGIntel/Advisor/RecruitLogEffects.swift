import Foundation

/// Exact Dark Gift definitions from the recorded games. Combat effects stay in the pinned simulator;
/// only an observed pending recruit increment is applied to the projected board here.
enum RecruitLogEffects {
    static func enabled(_ context: RecruitContext) -> Bool { context.policy.has(.recordedEffects) }

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
