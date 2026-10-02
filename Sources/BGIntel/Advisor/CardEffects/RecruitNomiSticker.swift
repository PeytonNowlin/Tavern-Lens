/// Nomi's accumulated shop buffs are already in observed stats. Only a new Elemental
/// play adds an increment, after its Battlecry; future refreshes remain unknown.
enum RecruitNomiSticker: RecruitCardEffect {
    static let lesser = "BG30_MagicItem_544"
    static let greater = "BG30_MagicItem_544t"
    static let cardIDs: Set<String> = [lesser, greater]
    static let since = 10

    private static func increment(_ id: String, context: RecruitContext) -> (Int, Int)? {
        guard (context.evaluationVersion ?? 0) >= 10 else { return nil }
        switch (id, context.text(id)) {
        case (lesser, "After you play an Elemental, give Elementals in the Tavern +3/+2 this game."):
            return (3, 2)
        case (greater, "After you play an Elemental, give Elementals in the Tavern +5/+5 this game."):
            return (5, 5)
        default: return nil
        }
    }

    static func trinketSupported(_ id: String, context: RecruitContext) -> Bool? {
        increment(id, context: context) != nil
    }

    private static func activeIncrement(_ state: RecruitState, context: RecruitContext) -> (Int, Int)? {
        let trinkets = state.input.playerBoard.player.trinkets.filter {
            $0.cardId == lesser || $0.cardId == greater
        }
        var attack = 0, health = 0
        for trinket in trinkets {
            guard let amount = increment(trinket.cardId, context: context) else { return nil }
            attack += amount.0; health += amount.1
        }
        return (attack, health)
    }

    /// New permanent shop scaling earned by this plan, for discounted future valuation.
    /// Steps contain only validated plays, and this search cannot change active trinkets.
    /// Never apply this total to observed shop stats: afterPlay already applies each increment.
    static func pendingShopBuff(in state: RecruitState, context: RecruitContext) -> (attack: Int, health: Int) {
        guard (context.evaluationVersion ?? 0) >= 10,
              let amount = activeIncrement(state, context: context) else { return (0, 0) }
        let plays = state.steps.filter { step in
            guard step.kind == .play, case .play(_, let id, _) = step.action,
                  let races = context.definitions[id]?.races else { return false }
            return races.contains("ELEMENTAL") || races.contains("ALL")
        }.count
        return (amount.0 * plays, amount.1 * plays)
    }

    static func afterPlay(before: RecruitState, state: inout RecruitState, context: RecruitContext) -> Bool {
        guard (context.evaluationVersion ?? 0) >= 10 else { return true }
        guard let amount = activeIncrement(before, context: context) else { return false }
        guard amount.0 > 0 || amount.1 > 0 else { return true }
        // A Battlecry can summon additional minions. Only the card moved from the
        // observed hand is played, so neither tokens nor Battlecry repeats retrigger Nomi.
        guard let played = before.hand.first(where: { card in
            state.board.contains { $0.entity.entityId == card.entity.entityId }
                && !before.board.contains { $0.entity.entityId == card.entity.entityId }
        }), let definition = context.definitions[played.cardID] else { return false }
        let races = definition.races ?? []
        guard races.contains("ELEMENTAL") || races.contains("ALL") else { return true }
        for i in state.shop.indices where state.shop[i].isMinion {
            guard let definition = context.definitions[state.shop[i].cardID] else { return false }
            let races = definition.races ?? []
            if races.contains("ELEMENTAL") || races.contains("ALL") {
                RecruitEffects.buff(&state.shop[i], attack: amount.0, health: amount.1)
            }
        }
        return true
    }
}
