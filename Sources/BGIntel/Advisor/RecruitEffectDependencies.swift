/// Generated entities are not necessarily present in an observed board. Capture the
/// exact build's deterministic dependencies now; search performs no live card lookups.
enum RecruitEffectDependencies {
    static func ids(for observed: [AdvisorCard]) -> [String] {
        let ids = Set(observed.map(\.cardID))
        var result: [String] = []
        if !ids.isDisjoint(with: ["BG36_201", "BG36_201_G"]) { result += ["BG36_205", "BG36_205_G"] }
        if !ids.isDisjoint(with: ["BG35_881", "BG35_881_G"]) { result += [RecruitPolicy11Spells.absorptionID] }
        return result
    }
}
