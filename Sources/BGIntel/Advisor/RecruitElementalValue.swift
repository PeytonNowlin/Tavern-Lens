import Foundation

/// Recurring engine estimates, separate from exact transitions and observed combat stats.
/// A tribe by itself has no value: an observed source must have a compatible recipient.
enum RecruitElementalValue {
    static func production(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> Double? {
        guard (context.evaluationVersion ?? 0) >= 10 else { return nil }
        switch card.cardID {
        case "BG34_858", "BG34_858_G":
            let reward = card.cardID == "BG34_858_G" ? "two Easterly Winds" : "Easterly Winds"
            guard context.text(card.cardID) == "After you spend 7 Gold, cast \(reward). (7 left!)",
                  context.text("BG34_444") == "After the Tavern is Refreshed this game, give a random minion in it +8/+8.",
                  let refreshCost = state.rollCost, refreshCost >= 0 else { return 0 }
            // One seven-Gold cycle establishes one recurring +8/+8 refresh buff. Half
            // its balanced-stat value is an option estimate: the recipient is unknown
            // and must still be bought. No historical Winds stack or pending-progress
            // tag is guessed, and no future buff is written to the combat board.
            return card.cardID == "BG34_858_G" ? 8 : 4
        case "BG31_812", "BG31_812_G":
            let suffix = card.cardID == "BG31_812_G" ? "." : " until next turn."
            guard context.text(card.cardID) == "Divine Shield Whenever you play an Elemental, give it Divine Shield\(suffix)" else { return 0 }
            // Two Ichorons do not grant two shields. Prefer the permanent source, then
            // a stable entity identity, so replacing a redundant copy costs no engine value.
            let sources = state.board.filter {
                ($0.cardID == "BG31_812" && context.text($0.cardID) == "Divine Shield Whenever you play an Elemental, give it Divine Shield until next turn.")
                    || ($0.cardID == "BG31_812_G" && context.text($0.cardID) == "Divine Shield Whenever you play an Elemental, give it Divine Shield.")
            }.sorted {
                if ($0.cardID == "BG31_812_G") != ($1.cardID == "BG31_812_G") { return $0.cardID == "BG31_812_G" }
                return $0.entity.entityId < $1.entity.entityId
            }
            guard sources.first?.entity.entityId == card.entity.entityId else { return 0 }
            var supply = state.hand.filter { eligible($0, context: context) }
            if state.hand.count < AdvisorRequest.handLimit {
                var gold = state.gold
                let offered = state.shop.filter { eligible($0, context: context) }.sorted { strength($0) > strength($1) }
                for target in offered {
                    let price = target.cost ?? AdvisorRequest.defaultMinionCost
                    guard price >= 0, price <= gold else { continue }
                    gold -= price; supply.append(target)
                }
            }
            // A quarter of the actual shield multiplier is the retained source's option
            // value. Played recipients leave this set; their observed shield is already
            // counted by tempo. Only known, currently usable supply contributes.
            return supply.sorted { strength($0) > strength($1) }.prefix(2).reduce(0) {
                $0 + min(8, strength($1) * 0.55 * 0.25)
            }
        case "BG32_843", "BG32_843_G":
            let suffix = card.cardID == "BG32_843_G" ? " twice." : "."
            guard context.text(card.cardID) == "At the end of your turn, give Elementals in the Tavern +4/+4 this game\(suffix)" else { return 0 }
            // This source grows Tavern Elementals, not every body in our warband.
            // Count only observed eligible recipients; off-tribe cards add no production.
            let recipients = state.shop.filter { isElemental($0, context: context) }
            return Double(min(2, recipients.count)) * (card.cardID == "BG32_843_G" ? 4 : 2)
                * Double(RecruitEffects.endOfTurnRepeats(state, context: context))
        default:
            return nil
        }
    }

    private static func isElemental(_ card: AdvisorCard, context: RecruitContext) -> Bool {
        guard card.isMinion, let races = context.definitions[card.cardID]?.races else { return false }
        return races.contains("ELEMENTAL") || races.contains("ALL")
    }

    private static func eligible(_ card: AdvisorCard, context: RecruitContext) -> Bool {
        isElemental(card, context: context) && !card.entity.locked && !card.entity.divineShield
    }

    private static func strength(_ card: AdvisorCard) -> Double {
        sqrt(Double(max(0, card.entity.attack)) * Double(max(1, card.entity.health)))
    }
}
