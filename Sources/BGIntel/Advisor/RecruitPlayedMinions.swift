/// Exact effects that happen when a hand minion is played, before its Battlecry.
/// Summoned tokens do not pass through this hook.
enum RecruitPlayedMinions {
    private static func shieldEnchantment(_ card: AdvisorCard, context: RecruitContext) -> String? {
        guard context.policy.has(.playedMinionEffects),
              card.cardID == "BG31_812" || card.cardID == "BG31_812_G" else { return nil }
        let enchantment: String
        let text: String
        switch (card.cardID, context.text(card.cardID)) {
        case ("BG31_812", "Divine Shield Whenever you play an Elemental, give it Divine Shield until next turn."):
            enchantment = "BG31_812e"
            text = "Divine Shield until next turn."
        case ("BG31_812_G", "Divine Shield Whenever you play an Elemental, give it Divine Shield."):
            enchantment = "BG31_812e2"
            text = "Divine Shield"
        default: return nil
        }
        guard context.definitions[enchantment]?.type == "ENCHANTMENT", context.text(enchantment) == text else { return nil }
        return enchantment
    }

    static func supported(_ card: AdvisorCard, context: RecruitContext) -> Bool {
        shieldEnchantment(card, context: context) != nil
    }

    static func prepare(_ played: inout AdvisorCard, before: RecruitState, state: inout RecruitState,
                        context: RecruitContext) -> Bool {
        let shields = before.board.compactMap { shieldEnchantment($0, context: context) }
        guard !shields.isEmpty else { return true }
        guard let definition = context.definitions[played.cardID] else { return false }
        let tribes = definition.races ?? []
        guard tribes.contains("ELEMENTAL") || tribes.contains("ALL") else { return true }
        played.entity.divineShield = true
        for enchantment in shields {
            // originEntityId identifies the attachment itself, not Ichoron's entity.
            played.entity.enchantments.append(BattleEnchantment(cardId: enchantment,
                originEntityId: state.nextEntityID))
            state.nextEntityID -= 1
        }
        // The normal attachment expires next recruit. This projection ends at combat;
        // the next request rebuilds its shield and enchantments from observed state.
        return true
    }
}
