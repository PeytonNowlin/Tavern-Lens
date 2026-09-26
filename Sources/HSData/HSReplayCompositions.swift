import Foundation

/// Allowlisted fields from public `script#react_context` composition guides. No account,
/// cookie, administrative, or gated statistics fields are retained.
public struct HSReplayCompositions: Codable, Sendable {
    public struct Comp: Codable, Sendable {
        public var comp_id: Int
        public var comp_name: String
        public var comp_slug: String
        public var comp_tier: Int?
        public var comp_difficulty: Int?
        public var comp_core_cards: [Int]
        public var comp_addon_cards: [Int]
        public var comp_last_updated: String?
        public var comp_tier_last_updated: String?
    }
    public var capturedAt: String
    public var comps: [Comp]

    public static func bundled() -> Self? {
        guard let url = HSDataResources.url("bg-pool/builds/hsreplay-comps.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    public func catalog(pool: MinionPool) -> BuildCatalog {
        let resolver = CardResolver(pool: pool)
        let recipes = Self.recipes()
        var builds: [BuildDefinition] = [], dropped: [BuildCatalog.Dropped] = []
        for comp in comps {
            let id = "hsreplay_\(comp.comp_id)"
            let core = comp.comp_core_cards.compactMap { pool.cards.card(dbfID: $0)?.id }
            guard core.count == comp.comp_core_cards.count, !core.isEmpty else {
                dropped.append(.init(id: id, reason: "Guide core contains unresolved card IDs")); continue
            }
            let addons = comp.comp_addon_cards.compactMap { pool.cards.card(dbfID: $0)?.id }
            let prefix = comp.comp_slug.split(separator: "-").first.map(String.init) ?? ""
            let tribe = ["beasts": "BEAST", "demons": "DEMON", "undead": "UNDEAD", "dragons": "DRAGON",
                         "murlocs": "MURLOC", "quilboar": "QUILBOAR", "pirates": "PIRATE", "mechs": "MECHANICAL",
                         "elementals": "ELEMENTAL"][prefix].flatMap { HS.Race(name: $0) }
            var build = BuildDefinition(id: id, name: comp.comp_name, tribes: tribe.map { [$0] } ?? [],
                core: core, addons: addons, whenToCommit: nil, tip: nil,
                difficulty: comp.comp_difficulty.flatMap { [1: "Easy", 2: "Medium", 3: "Hard"][$0] },
                powerLevel: comp.comp_tier.map { "Tier \($0)" }, source: .hsreplay)
            if let recipe = recipes[String(comp.comp_id)] {
                build.requirements = recipe.requirements.map { requirement in
                    BuildRequirement(role: requirement.role,
                        anyOf: requirement.dbfIDs.compactMap { pool.cards.card(dbfID: $0)?.id })
                }
                build.tip = recipe.guidance
                build.whenToCommit = recipe.requirements.map { requirement in
                    let names = requirement.dbfIDs.compactMap { pool.cards.card(dbfID: $0)?.name }
                    return requirement.role + (names.isEmpty ? " (not verified)" : ": " + names.joined(separator: " or "))
                }.joined(separator: "; ")
            }
            build.sourceEvidence = BuildEvidence(provider: "HSReplay", url: "https://hsreplay.net/battlegrounds/comps/\(comp.comp_id)/\(comp.comp_slug)",
                capturedAt: capturedAt, sourceUpdated: comp.comp_last_updated, tierUpdated: comp.comp_tier_last_updated)
            switch BuildCatalog.filtered(build, curatedCore: Set(core), resolver: resolver) {
            case .success(let kept): builds.append(kept)
            case .failure(let reason): dropped.append(.init(id: id, reason: reason.text))
            }
        }
        var bases: [String: String] = [:]
        for build in builds {
            for card in build.core + build.addons {
                for golden in resolver.goldens(of: card) { bases[golden] = card }
            }
        }
        return BuildCatalog(builds: builds, dropped: dropped, goldenToBase: bases)
    }

    private struct Recipe: Decodable {
        struct Requirement: Decodable { var role: String; var dbfIDs: [Int] }
        var requirements: [Requirement]
        var guidance: String
    }
    private static func recipes() -> [String: Recipe] {
        guard let url = HSDataResources.url("bg-pool/builds/strategy-recipes.json"),
              let data = try? Data(contentsOf: url), let recipes = try? JSONDecoder().decode([String: Recipe].self, from: data)
        else { return [:] }
        return recipes
    }
}
