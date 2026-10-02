import Foundation

/// A small observed-placement tie breaker, independent of legality and combat projection.
public enum RecruitCardTurnPrior {
    public static let maximumPlanInfluence = 0.75
    /// Later comparisons are sparse and increasingly selected by survival/build commitment.
    public static let supportedTurns = 1...3

    public static func value(_ state: RecruitState, request: AdvisorRequest, context: RecruitContext) -> Double {
        guard context.policy.has(.cardTurnPrior),
              supportedTurns.contains(request.preview.bgTurn),
              let stats = request.cardTurnStats, let checkedAt = request.cardTurnStatsCheckedAt,
              stats.usable(now: checkedAt) else { return 0 }
        let bought = Set(state.steps.filter { $0.kind == .buy }.map(\.entityID))
        let existing = Set(request.board.map { $0.entity.entityId })
        var result = 0.0
        for card in state.board where bought.contains(card.entity.entityId) && !existing.contains(card.entity.entityId) {
            // The source row is for the observed shop card, rather than a generated triple,
            // token, free reward or pre-existing board member.
            guard request.shop.contains(where: { $0.entity.entityId == card.entity.entityId && $0.cardID == card.cardID }),
                  let entry = stats.entry(cardID: card.cardID, turn: request.preview.bgTurn, now: checkedAt) else { continue }
            let population = Double(min(entry.totalPlayed, entry.totalOther))
            let shrinkage = population / (population + 1000)
            result += max(0, min(0.4, -entry.impact * shrinkage))
        }
        return min(maximumPlanInfluence, result)
    }
}
