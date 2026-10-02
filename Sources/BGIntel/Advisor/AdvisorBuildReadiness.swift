import HSData

/// Policy corrections apply to captured recipes as well as newly loaded catalog data.
/// Selection and plan scoring must agree on what constitutes a working engine.
enum AdvisorBuildReadiness {
    static func roleCards(board: [AdvisorCard], hand: [AdvisorCard], evaluationVersion: Int?,
                          base: (String) -> String) -> Set<String> {
        let usableHand = (evaluationVersion ?? 0) >= 10 ? hand.filter { !$0.entity.locked } : hand
        return Set((board + usableHand).map { base($0.cardID) })
    }

    static func requirements(_ build: AdvisorBuild, evaluationVersion: Int?) -> [BuildRequirement]? {
        guard (evaluationVersion ?? 0) >= 10, build.id == "hsreplay_8" else { return build.requirements }
        return build.requirements?.map { requirement in
            guard requirement.role == "Venom replacement" else { return requirement }
            // Aviator supplies no lethal effect itself. Its hand-dependent payoff cannot
            // be represented by this recipe's simple OR list; retain it as optional utility.
            return BuildRequirement(role: requirement.role,
                anyOf: requirement.anyOf.filter { $0 != "BG34_140" && $0 != "BG34_140_G" })
        }
    }
}
