import Foundation
import HSData

/// A direction is an opportunity, not a promise that future shops will supply its cards.
public struct AdvisorStrategy: Codable, Hashable, Sendable {
    public var buildID: String
    public var name: String
    public var committed: Bool
    public var missing: [String]
    public var missingRequirements: [BuildRequirement]?
    public var alternatives: [String]
    public var unverifiedRequirements: [String]
    public var acquisition: String
    public var search: Acquisition?

    public struct Acquisition: Codable, Hashable, Sendable {
        public var eligibleTargets: [String]
        public var poolTypes: Int?
        public var minimumPurchaseGold: Int
        public var affordableRefreshes: Int
    }
    public var reason: String
    public var commitment: String?
    public var guidance: String?
    public var fallback: String
    public var source: String?
    public var sourceUpdated: String?

    public struct Selection: Sendable {
        public var build: AdvisorBuild
        public var guidance: AdvisorStrategy
    }

    public static func select(_ request: AdvisorRequest) -> Selection? {
        let base: (String) -> String = { request.baseCardIDs?[$0] ?? request.recruit?.base($0) ?? ($0.hasSuffix("_G") ? String($0.dropLast(2)) : $0) }
        let held = Set((request.board + request.hand).map { base($0.cardID) })
        let offered = Set(request.shop.filter { ($0.cost ?? 3) <= request.gold }.map { base($0.cardID) })
        let health = request.recruit?.input.playerBoard.player.hpLeft ?? 30
        let catalog = request.strategyCatalog ?? request.builds ?? []
        var production: [String: Double] = [:]
        if let context = request.recruit {
            let state = RecruitState(request: request, context: context)
            for card in request.board {
                production[base(card.cardID), default: 0] += RecruitPlanner.production(card, state: state, context: context)
            }
        }
        let ranked = catalog.compactMap { build -> (AdvisorBuild, Double)? in
            let owned = held.intersection(build.core).count
            let available = offered.subtracting(held).intersection(build.core).count
            guard owned > 0 || available > 0 else { return nil }
            let support = held.intersection(build.addons).count
            let distant = build.core.filter { !held.contains($0) && !offered.contains($0) && (build.coreTiers[$0] ?? request.tier) > request.tier + 1 }.count
            // Shared utility pieces alone cannot outweigh several defining pieces already held.
            let rarity = build.core.filter(held.contains).reduce(0.0) { total, card in
                total + 1 / Double(max(1, catalog.filter { $0.core.contains(card) }.count))
            }
            // End-board placement is a small contextual prior, never a causal purchase value.
            let prior = build.evidenceIsStale == false && (build.placementEvidence?.sampleSize ?? 0) >= 50
                ? max(-0.5, min(0.5, (4.5 - (build.averagePlacement ?? 4.5)) * 0.25)) : 0
            // Reuse the planner's supported resource/seasonal estimates so direction and
            // action evaluation see the same hero, trinket, gift and Deity context.
            let contextual = min(4, build.core.reduce(0.0) { $0 + (production[$1] ?? 0) } * 0.25)
            let editorial = (build.editorialTierIsFresh == true ? build.editorialTier : nil).map { max(0, min(0.5, Double(3 - $0) * 0.25)) } ?? 0
            return (build, prior + editorial + contextual + Double(owned * 4 + available * 2 + (owned > 0 ? support : 0) - distant * 2) + rarity)
        }.sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 > $1.1 }
        guard let best = ranked.first, best.1 > 0 else { return nil }
        var build = best.0
        let owned = held.intersection(build.core).count
        let requirements = build.requirements ?? []
        let ready = !requirements.isEmpty && requirements.allSatisfy { !held.intersection($0.anyOf).isEmpty }
        let committed = ready && owned > 0 && health > 5
        build.share = health <= 5 ? 0.15 : committed ? 1 : 0.5
        let missing = requirements.isEmpty ? build.core.filter { !held.contains($0) && !offered.contains($0) }
            : requirements.filter { held.union(offered).intersection($0.anyOf).isEmpty }.flatMap(\.anyOf)
        let missingRoles = requirements.isEmpty ? missing.map { BuildRequirement(role: "Core", anyOf: [$0]) }
            : requirements.filter { held.union(offered).intersection($0.anyOf).isEmpty }
        let pendingRoles = requirements.isEmpty ? build.core.filter { !held.contains($0) }.map { BuildRequirement(role: "Core", anyOf: [$0]) }
            : requirements.filter { held.intersection($0.anyOf).isEmpty }
        let reserve = pendingRoles.filter { !$0.anyOf.isEmpty }.reduce(0) { total, role in
            let prices = request.shop.filter { role.anyOf.contains(base($0.cardID)) }.map { $0.cost ?? 3 }
            return total + (prices.min() ?? AdvisorRequest.defaultMinionCost)
        }
        let tierBlocked = missingRoles.contains { !$0.anyOf.isEmpty && $0.anyOf.allSatisfy {
            (request.poolTiers?[$0] ?? build.coreTiers[$0] ?? 0) > request.tier
        } }
        return Selection(build: build, guidance: AdvisorStrategy(
            buildID: build.id, name: build.name, committed: committed, missing: missing, missingRequirements: missingRoles,
            alternatives: ranked.dropFirst().prefix(2).map { $0.0.name },
            unverifiedRequirements: requirements.filter { $0.anyOf.isEmpty }.map(\.role),
            acquisition: tierBlocked
                ? "Some targets need a higher tier; do not roll for them yet"
                : "Reserve purchase gold before rolling; shop odds and contested copies are unknown",
            search: Acquisition(
                eligibleTargets: missing.filter { (request.poolTiers?[$0] ?? build.coreTiers[$0] ?? Int.max) <= request.tier },
                poolTypes: request.poolTiers.map { $0.values.filter { $0 <= request.tier }.count },
                minimumPurchaseGold: reserve,
                affordableRefreshes: request.rollCost.map { $0 > 0 ? max(0, request.gold - max(3, reserve)) / $0 : 0 } ?? 0),
            reason: health <= 5 ? "Survive this combat before investing in a build" : committed
                ? "The required engine pieces are already held" : owned > 0
                    ? "Some pieces are held; the engine is not yet verified" : "An affordable core piece is offered; keep this direction open",
            commitment: build.commitment, guidance: build.guidance,
            fallback: "Buy immediate strength if the missing pieces do not appear; reassess after each shop",
            source: build.source, sourceUpdated: [build.sourceUpdated, build.evidence?.tierUpdated.map { "Tier updated: " + $0 },
                build.editorialTierIsFresh == false ? "Editorial tier stale/unknown; excluded from ranking" : nil].compactMap { $0 }.joined(separator: " · ")))
    }
}
