import Foundation

/// Locket copies are casts by the trinket. They do not play another card or trigger
/// hero-only spell counters/listeners. Unknown copy outcomes end this plan at the cast.
enum RecruitLovelyLocket: RecruitCardEffect {
    static let locketID = "BG36_MagicItem_211"
    static let locketText = "After you cast a spell on a friendly minion, this casts it on another friendly minion."
    static let cardIDs: Set<String> = [locketID]
    static let since = 8

    private static func supported(_ context: RecruitContext) -> Bool { context.text(locketID) == locketText }

    /// Targeted player casts are resolved or limited per action by `afterPlayerSpell`.
    static func trinketSupported(_ id: String, context: RecruitContext) -> Bool? { supported(context) }

    static func afterPlayerSpell(_ step: RecruitStep, before: RecruitState, state: inout RecruitState,
                                 context: RecruitContext) -> Bool {
        guard step.kind == .spell, supported(context),
              let target = step.targetID, before.board.contains(where: { $0.entity.entityId == target }),
              let card = (before.hand + before.shop).first(where: { $0.entity.entityId == step.entityID }) else { return true }
        let lockets = state.input.playerBoard.player.trinkets.filter { $0.cardId == locketID }
        guard !lockets.isEmpty else { return true }
        let others = state.board.filter {
            $0.entity.entityId != target && $0.entity.health > 0
                && RecruitCardEffects.spellTargetAllowed(card, target: $0.entity.entityId, state: state, context: context)
        }

        // Existing spell transitions only model a single cast (plus the hand-Gem aura).
        // These sources require a separate original/copy event sequence for each repeat.
        if before.board.contains(where: { ["BG35_883", "BG35_883_G", "BG34_922", "BG34_922_G"].contains($0.cardID) })
            || before.input.playerBoard.player.trinkets.contains(where: { $0.cardId == "BG30_MagicItem_434" }) {
            return unresolved("Lovely Locket with repeated spell casts: resolve the spell and reassess", state: &state)
        }
        if card.cardID == "BG20_GEM" {
            if before.board.contains(where: { context.text($0.cardID) == "Blood Gems played from your hand cast an extra time." }) {
                return unresolved("Lovely Locket with repeated Blood Gems: resolve the spell and reassess", state: &state)
            }
            // Gem-on-minion reactions and cumulative gem enchantments are distinct from
            // generic stat buffs. Keep affected plans uncertain until those are modelled.
            let gemRecipients: Set<String> = ["BG32_431", "BG32_431_G", "BG34_Giant_104", "BG34_Giant_104_G",
                "BG20_102", "BG20_102_G", "BG28_583", "BG28_583_G", "BG20_302", "BG20_302_G", "BG25_039", "BG25_039_G"]
            let recipients = state.board.filter { $0.entity.entityId == target } + others
            if recipients.contains(where: { gemRecipients.contains($0.cardID) })
                || before.board.contains(where: { ["BG32_432", "BG32_432_G", "BG34_PreMadeChamp_076", "BG34_PreMadeChamp_076_G"].contains($0.cardID) })
                || before.input.playerBoard.player.trinkets.contains(where: { $0.cardId == "BG30_MagicItem_442" }) {
                return unresolved("Lovely Locket Blood Gem reactions are unmodelled; resolve the spell and reassess", state: &state)
            }
        }
        guard !others.isEmpty else { return true }
        guard lockets.count == 1 else {
            return unresolved("Multiple Lovely Lockets: resolve the copied spells and reassess", state: &state)
        }
        guard others.count == 1 else {
            return unresolved("Lovely Locket copy target is random; resolve the spell and reassess", state: &state)
        }
        // Board after-cast effects have resolved before trinket after-cast effects. Read
        // current Gem bonuses here, and deliberately bypass hero-only event dispatch.
        let effect = RecruitPlanner.spellEffect(card, state: state, context: context)
        guard RecruitEffects.needsTarget(effect) else { return true }
        return RecruitEffects.apply(effect, target: others[0].entity.entityId, state: &state, context: context)
    }

    private static func unresolved(_ reason: String, state: inout RecruitState) -> Bool {
        state.limitations.append(reason)
        state.terminal = true
        return true
    }
}
