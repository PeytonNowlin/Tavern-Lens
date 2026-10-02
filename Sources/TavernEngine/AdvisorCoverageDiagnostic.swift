import Foundation
import BGIntel

/// Coverage at the captured decision, so the next audit can distinguish unavailable
/// metadata, unobserved state and unimplemented effects without rerunning a live feed.
public struct AdvisorCoverageDiagnostic: Codable, Hashable, Sendable {
    public struct Gap: Codable, Hashable, Sendable {
        public enum Kind: String, Codable, Sendable { case metadata, state, effect }
        public var kind: Kind
        public var reason: String
        public var cardIDs: [String]
    }
    public var policyVersion: Int
    public var missingDefinitions: [String]
    public var gaps: [Gap]
    public var cardTurnEvidence: [String]
    public var cardTurnSourceDate: String?

    public init(request: AdvisorRequest, policyVersion: Int) {
        self.policyVersion = policyVersion
        let visible = request.board + request.hand + request.shop
        missingDefinitions = Set(visible.map(\.cardID).filter { request.recruit?.definitions[$0] == nil }).sorted()
        gaps = []
        if var context = request.recruit {
            context.evaluationVersion = policyVersion
            let search = RecruitPlanner.search(request, context: context,
                budget: .init(depth: 0, width: 1, expansions: 0))
            gaps = search.limitations.map { reason in
                let lower = reason.lowercased()
                let kind: Gap.Kind = lower.contains("missing card definitions") ? .metadata
                    : lower.contains("unknown") || lower.contains("unobserved") || lower.contains("not captured") ? .state : .effect
                let ids = context.definitions.values.filter { card in
                    reason.hasSuffix(": \(card.id)") || (!card.name.isEmpty && reason.hasSuffix(": \(card.name)"))
                }.map(\.id).sorted()
                return Gap(kind: kind, reason: reason, cardIDs: ids)
            }
            if context.policy.has(.coverageDiagnostics) {
                let unknownCosts = Set(visible.filter {
                    context.activations?[$0.entity.entityId]?.costObserved == false
                }.map(\.cardID)).sorted()
                gaps += unknownCosts.map { id in
                    Gap(kind: .state, reason: "Activate cost is unobserved: \(context.definitions[id]?.name ?? id)",
                        cardIDs: [id])
                }
            }
        }
        cardTurnSourceDate = request.cardTurnStats?.lastUpdateDate
        cardTurnEvidence = request.cardTurnStats?.cardStats.map(\.cardId).sorted() ?? []
    }
}
