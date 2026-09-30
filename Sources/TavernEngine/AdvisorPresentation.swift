import BGIntel
import Foundation
import HSData

/// The advisor's display contract. It formats existing decisions without ranking them again.
public struct AdvisorPresentation: Sendable {
    public enum State: Equatable, Sendable {
        case unavailable, updating, thinking, noData, tentative, recommendation, choice
    }

    public struct Suggestion: Sendable {
        public let rank: Int
        public let title: String
        public let reason: String
        public let confidence: AdvisorConfidence
        public let targets: [AdvisorTarget]
        public let steps: [String]
        public let limitations: [String]

        fileprivate init(_ suggestion: AdvisorSuggestion, name: (String) -> String) {
            rank = suggestion.rank
            reason = suggestion.reason
            confidence = suggestion.confidence
            limitations = suggestion.limitations ?? []
            if let continuation = suggestion.continuation, !continuation.isEmpty {
                title = continuation[0]
                steps = continuation
                targets = suggestion.targets
            } else if case .swap(let shop, let card, let board, let sold) = suggestion.action {
                // Archived single-action plans combine the prerequisite and the purchase.
                title = suggestion.action.title(name: name)
                steps = ["Sell \(name(sold))", "Buy \(name(card))"]
                targets = [.init(.board, board), .init(.shop, shop)]
            } else {
                title = suggestion.action.title(name: name)
                steps = [title]
                targets = suggestion.targets
            }
        }
    }

    public struct Requirement: Sendable {
        public enum State: Equatable, Sendable { case owned, available, required, unverified }
        public let role: String
        /// Held or affordable matching cards for those states; all alternatives when required.
        public let cards: [String]
        public let state: State
    }

    public let state: State
    public let title: String
    public let reason: String
    /// Evaluation-wide caveats, kept separate from the action's reason and continuation.
    public let note: String?
    /// The first actionable trust caveat; the complete evaluation note remains in details.
    public let caveat: String?
    /// Present only for a current recommendation. Tentative options belong in details.
    public let primary: Suggestion?
    public let alternatives: [Suggestion]
    public let topSuggestion: AdvisorSuggestion?
    public let currentFits: [DetectedBuildView]
    public let direction: AdvisorStrategy?
    public let choice: AdvisorChoice?
    /// Empty without the exact request that produced this advice; absence is not ownership.
    public let requirements: [Requirement]

    public init(
        advice: AdviceView, request: AdvisorRequest? = nil, detectedBuilds: [DetectedBuildView] = [],
        name: (String) -> String = { $0 }
    ) {
        currentFits = detectedBuilds
        let content = advice.advice
        if advice.failure != nil { state = .unavailable }
        else if advice.isUpdating { state = .updating }
        else if content.status == .thinking { state = .thinking }
        else if content.choice != nil { state = .choice }
        else if content.status == .noData { state = .noData }
        else if content.status == .recommendation, !content.suggestions.isEmpty { state = .recommendation }
        else { state = .tentative }

        let showsDetails = state == .recommendation || state == .tentative || state == .choice
        note = showsDetails ? content.note : nil
        direction = showsDetails ? content.strategy : nil
        choice = state == .choice ? content.choice : nil
        let suggestions = showsDetails && choice == nil ? content.suggestions : []
        topSuggestion = suggestions.first
        let noteClauses = Self.meaningfulNoteClauses(content.note)
        caveat = showsDetails ? suggestions.first?.limitations?.first ?? noteClauses.first : nil
        let options = suggestions.map { Suggestion($0, name: name) }
        primary = state == .recommendation ? options.first : nil
        alternatives = primary == nil ? options : Array(options.dropFirst())

        switch state {
        case .unavailable:
            title = "Advisor unavailable"
            reason = advice.failure ?? "Advice is temporarily unavailable."
        case .updating:
            title = "Updating advice…"
            reason = "Your position changed. Checking the next action."
        case .thinking:
            title = "Thinking…"
            reason = "Checking your board, shop and gold."
        case .noData:
            title = "Advice unavailable"
            reason = content.note ?? "Waiting for enough information."
        case .tentative:
            title = "No strong recommendation"
            reason = noteClauses.isEmpty ? "The options are close or the evidence is limited."
                : noteClauses.joined(separator: " · ")
        case .recommendation:
            title = primary?.title ?? "Advisor"
            reason = primary?.reason ?? content.note ?? ""
        case .choice:
            title = choice.map { "Consider \($0.name)" } ?? "Finish the current choice"
            reason = choice?.reason ?? content.note ?? "Reassess after choosing."
        }

        if let direction, let request,
           AdviceView.fingerprint(of: request, version: advice.plan.version) == advice.fingerprint,
           let build = (request.strategyCatalog ?? request.builds ?? []).first(where: { $0.id == direction.buildID }) {
            requirements = Self.requirements(build, request: request, name: name)
        } else {
            requirements = []
        }
    }

    private static func meaningfulNoteClauses(_ note: String?) -> [String] {
        let neutral = [
            "Plans use your board, scaling and gold",
            "Combat checks use recent boards + stronger stress scenarios",
        ]
        return (note?.components(separatedBy: " · ") ?? []).filter { !neutral.contains($0) && !$0.isEmpty }
    }

    private static func requirements(
        _ build: AdvisorBuild, request: AdvisorRequest, name: (String) -> String
    ) -> [Requirement] {
        func base(_ id: String) -> String {
            request.baseCardIDs?[id] ?? request.recruit?.base(id)
                ?? (id.hasSuffix("_G") ? String(id.dropLast(2)) : id)
        }
        let held = Set((request.board + request.hand).map { base($0.cardID) })
        let affordable = Set(request.shop.filter {
            ($0.cost ?? AdvisorRequest.defaultMinionCost) <= request.gold
        }.map { base($0.cardID) })
        let roles = build.requirements.flatMap { $0.isEmpty ? nil : $0 }
            ?? build.core.map { BuildRequirement(role: "Core", anyOf: [$0]) }
        return roles.map { role in
            let alternatives = Set(role.anyOf.map(base))
            let state: Requirement.State
            let matchingCards: [String]
            if alternatives.isEmpty {
                state = .unverified
                matchingCards = []
            } else if !held.isDisjoint(with: alternatives) {
                state = .owned
                matchingCards = role.anyOf.filter { held.contains(base($0)) }
            } else if !affordable.isDisjoint(with: alternatives) {
                state = .available
                matchingCards = role.anyOf.filter { affordable.contains(base($0)) }
            } else {
                state = .required
                matchingCards = role.anyOf
            }
            return Requirement(role: role.role, cards: matchingCards.map(name), state: state)
        }
    }
}
