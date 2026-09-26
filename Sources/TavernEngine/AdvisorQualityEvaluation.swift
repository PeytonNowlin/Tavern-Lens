import Foundation
import BGIntel

/// A frozen decision and optional independent review. Split corpora by entire game and patch,
/// not by individual turns. Unreviewed cases contribute coverage, never preference evidence.
public struct AdvisorQualityCase: Codable, Sendable {
    public var name: String
    public var request: AdvisorRequest
    public var reviewer: String?
    public var acceptableActions: [String]?
    public var prohibitedActions: [String]?
    public var acceptableBuilds: [String]?
    public init(name: String, request: AdvisorRequest, reviewer: String? = nil,
                acceptableActions: [String]? = nil, prohibitedActions: [String]? = nil,
                acceptableBuilds: [String]? = nil) {
        self.name = name; self.request = request; self.reviewer = reviewer
        self.acceptableActions = acceptableActions; self.prohibitedActions = prohibitedActions
        self.acceptableBuilds = acceptableBuilds
    }
}

public enum AdvisorQualityEvaluation {
    public struct Row: Codable, Sendable {
        public var name: String
        public var advice: Advice
        public var evaluations: Int
        public var available: Bool
        public var unsupported: Bool
        public var reviewed: Bool
        public var accepted: Bool?
        public var severeError: Bool?
    }
    public struct Report: Codable, Sendable {
        public var version: Int
        public var rows: [Row]
        public var decisions: Int { rows.count }
        public var available: Int { rows.filter(\.available).count }
        public var reviewed: Int { rows.filter(\.reviewed).count }
        public var accepted: Int { rows.filter { $0.accepted == true }.count }
        public var severeErrors: Int { rows.filter { $0.severeError == true }.count }
        public var unsupported: Int { rows.filter(\.unsupported).count }
    }

    public static func run(_ cases: [AdvisorQualityCase], plan: AdvisorPlan,
                           simulate: AdvisorEvaluation.Simulate) async throws -> Report {
        var rows: [Row] = []
        for item in cases {
            try Task.checkCancellation()
            let result = try await AdvisorEvaluation.run(item.request, plan: plan, simulate: simulate)
            let advice = result.advice
            let action = advice.suggestions.first?.action.id
            let reviewed = item.reviewer?.isEmpty == false
            let severe = item.prohibitedActions.map { action.map($0.contains) ?? false }
            let acceptedAction = item.acceptableActions.map { action.map($0.contains) ?? false }
            let acceptedBuild = item.acceptableBuilds.map { advice.strategy.map { $0.buildID }.map($0.contains) ?? false }
            let judgements = [acceptedAction, acceptedBuild].compactMap { $0 }
            rows.append(Row(name: item.name, advice: advice, evaluations: result.evaluations,
                available: !advice.suggestions.isEmpty || advice.choice != nil,
                unsupported: advice.suggestions.contains { !($0.limitations ?? []).isEmpty }
                    || advice.note?.contains("Unmodelled") == true,
                reviewed: reviewed,
                accepted: reviewed && !judgements.isEmpty ? judgements.allSatisfy { $0 } : nil,
                severeError: reviewed ? severe : nil))
        }
        return Report(version: plan.version, rows: rows)
    }
}
