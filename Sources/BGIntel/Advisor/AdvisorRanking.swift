/// One candidate's simulation results, accumulated over its scoring passes.
public struct CombatTally: Codable, Hashable, Sendable {
    public var simulations = 0
    /// Counts (fractional: the simulator reports percentages).
    public var won = 0.0
    public var tied = 0.0
    public var lost = 0.0
    public var wonLethal = 0.0
    public var lostLethal = 0.0
    /// Damage to the loser's hero, summed over the simulations won (dealt) and lost (taken).
    public var damageDealt = 0.0
    public var damageTaken = 0.0

    public init() {}

    /// Adds one simulator result (percentages and average damage, as `CombatOdds` has them).
    public mutating func add(
        simulations n: Int, won: Double, tied: Double, lost: Double, wonLethal: Double, lostLethal: Double,
        averageDamageWon: Double, averageDamageLost: Double
    ) {
        guard n > 0 else { return }
        let scale = Double(n) / 100
        simulations += n
        self.won += won * scale
        self.tied += tied * scale
        self.lost += lost * scale
        self.wonLethal += wonLethal * scale
        self.lostLethal += lostLethal * scale
        damageDealt += averageDamageWon * won * scale
        damageTaken += averageDamageLost * lost * scale
    }

    private func percent(_ count: Double) -> Double { simulations > 0 ? count / Double(simulations) * 100 : 0 }
    public var winPercent: Double { percent(won) }
    public var tiePercent: Double { percent(tied) }
    public var lossPercent: Double { percent(lost) }
    public var lethalRiskPercent: Double { percent(lostLethal) }
    /// Per simulation, over all of them.
    public var averageDamageDealt: Double { simulations > 0 ? damageDealt / Double(simulations) : 0 }
    public var averageDamageTaken: Double { simulations > 0 ? damageTaken / Double(simulations) : 0 }
    /// Win equity: a win counts 1, a tie ½, in percent.
    public var equity: Double { percent(won + tied / 2) }

    /// The standard error of `equity`, in percentage points (a floor of ½ a simulation keeps it
    /// above zero for sure wins and losses).
    public var standardError: Double {
        guard simulations > 0 else { return 100 }
        let n = Double(simulations)
        let p = min(max(equity / 100, 0.5 / n), 1 - 0.5 / n)
        return (p * (1 - p) / n).squareRoot() * 100
    }

    /// The standard error of `Advisor.value`: equity's, plus the damage term's. The simulator
    /// reports only average damage, so its spread is taken as about the average itself.
    public func valueStandardError(_ weights: AdvisorWeights) -> Double {
        guard simulations > 0 else { return 100 }
        let damage = (weights.damageDealtPerHealth * averageDamageDealt + weights.damageTakenPerHealth * averageDamageTaken)
            / Double(simulations).squareRoot()
        return weights.combat * (standardError * standardError + damage * damage).squareRoot()
    }
}

/// How candidates are valued and when a suggestion counts as confident. Configurable so #20's
/// blended scoring (lobby, build and economy terms) and its tuning from bookmarked cases slot in.
public struct AdvisorWeights: Codable, Hashable, Sendable {
    /// The weight of the combat term (the next combat against the next opponent's last-seen board).
    public var combat = 1.0
    /// Value, in percentage points of win equity, per hero health of expected damage taken (a loss
    /// that costs 5 health less is worth 5 points) and dealt (worth less: it only hurts one opponent).
    public var damageTakenPerHealth = 1.0
    public var damageDealtPerHealth = 0.5
    /// Value lost per percentage point of risk that the combat kills the player (on top of the loss).
    public var lethalRisk = 1.0
    /// A board change counts as an improvement when it gains at least this much value…
    public var minimumGain = 1.0
    /// …and this many standard errors of the difference.
    public var minimumZ = 1.0
    /// A suggestion's gain, in standard errors, for high and medium confidence.
    public var highZ = 3.0
    public var mediumZ = 1.5
    /// An opponent board seen this many turns ago or more gives at most medium confidence.
    public var staleAfterTurns = 3
    /// Fewer simulations behind a suggestion than this give low confidence.
    public var minimumSimulations = 150
    /// How many suggestions the advisor shows.
    public var suggestions = 3

    public static let standard = AdvisorWeights()

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case combat, damageTakenPerHealth, damageDealtPerHealth, lethalRisk, minimumGain, minimumZ, highZ, mediumZ
        case staleAfterTurns, minimumSimulations, suggestions
    }

    /// Weights missing from saved advice (a bookmark from before a weight existed) take today's
    /// defaults, so saved records keep loading as weights are added.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try c.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        let d = AdvisorWeights()
        combat = try value(.combat, d.combat)
        damageTakenPerHealth = try value(.damageTakenPerHealth, d.damageTakenPerHealth)
        damageDealtPerHealth = try value(.damageDealtPerHealth, d.damageDealtPerHealth)
        lethalRisk = try value(.lethalRisk, d.lethalRisk)
        minimumGain = try value(.minimumGain, d.minimumGain)
        minimumZ = try value(.minimumZ, d.minimumZ)
        highZ = try value(.highZ, d.highZ)
        mediumZ = try value(.mediumZ, d.mediumZ)
        staleAfterTurns = try value(.staleAfterTurns, d.staleAfterTurns)
        minimumSimulations = try value(.minimumSimulations, d.minimumSimulations)
        suggestions = try value(.suggestions, d.suggestions)
    }
}

/// The parts of a suggestion's value. #19 scores the next combat only; #20 fills in the rest.
public struct AdvisorTerms: Codable, Hashable, Sendable {
    /// The next combat's value gained over keeping the board (percentage points of win equity,
    /// adjusted for damage and lethal risk).
    public var combat: Double
    public var lobby: Double?
    public var build: Double?
    public var economy: Double?

    public init(combat: Double, lobby: Double? = nil, build: Double? = nil, economy: Double? = nil) {
        self.combat = combat
        self.lobby = lobby
        self.build = build
        self.economy = economy
    }
}

public enum AdvisorConfidence: String, Codable, Hashable, Sendable {
    case high, medium, low
}

/// The next combat's odds as a suggestion (or the board as it is) would fight it.
public struct AdvisorOdds: Codable, Hashable, Sendable {
    public var won: Double
    public var tied: Double
    public var lost: Double
    /// The chance the combat kills the local player.
    public var lethalRisk: Double
    public var averageDamageDealt: Double
    public var averageDamageTaken: Double
    public var simulations: Int

    init(_ tally: CombatTally) {
        won = Self.rounded(tally.winPercent)
        tied = Self.rounded(tally.tiePercent)
        lost = Self.rounded(tally.lossPercent)
        lethalRisk = Self.rounded(tally.lethalRiskPercent)
        averageDamageDealt = Self.rounded(tally.averageDamageDealt)
        averageDamageTaken = Self.rounded(tally.averageDamageTaken)
        simulations = tally.simulations
    }

    /// Two decimals, so golden JSON stays readable.
    static func rounded(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}

/// One ranked suggestion.
public struct AdvisorSuggestion: Codable, Hashable, Sendable {
    /// 1 for the best.
    public var rank: Int
    public var action: AdvisorAction
    /// What to highlight in place, most important first.
    public var targets: [AdvisorTarget]
    /// One line: why, such as "+11% win vs next opponent".
    public var reason: String
    public var confidence: AdvisorConfidence
    /// The next combat with the action taken; the board as it is for level, roll and freeze.
    public var odds: AdvisorOdds?
    /// The value gained over keeping the board (0 for actions that don't change it).
    public var gain: Double
    public var terms: AdvisorTerms
}

/// What the advisor shows for one recruit-phase state.
public struct Advice: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Hashable, Sendable {
        /// Nothing scored yet.
        case thinking
        case recommendation
        /// The options are close, or the data is thin: the suggestions are there, but none stands out.
        case noStrongRecommendation
        /// The next opponent hasn't been seen, so there's nothing to simulate against.
        case noData
    }

    public var status: Status
    /// Why there's no strong recommendation (or no data), or a caveat about the data.
    public var note: String?
    /// The next combat with the board as it is.
    public var baseline: AdvisorOdds?
    /// Best first; at most `AdvisorWeights.suggestions`.
    public var suggestions: [AdvisorSuggestion]
    /// Candidates scored so far, of those generated so far.
    public var scored: Int
    public var candidates: Int

    public init(
        status: Status, note: String? = nil, baseline: AdvisorOdds? = nil, suggestions: [AdvisorSuggestion] = [],
        scored: Int = 0, candidates: Int = 0
    ) {
        self.status = status
        self.note = note
        self.baseline = baseline
        self.suggestions = suggestions
        self.scored = scored
        self.candidates = candidates
    }

    public static let noData = Advice(status: .noData, note: "No data: next opponent not fought yet")
}

extension Advisor {
    /// A candidate's value: the combat term (win equity, adjusted for damage and lethal risk).
    public static func value(_ tally: CombatTally, weights: AdvisorWeights = .standard) -> Double {
        let combat = tally.equity + weights.damageDealtPerHealth * tally.averageDamageDealt
            - weights.damageTakenPerHealth * tally.averageDamageTaken
            - weights.lethalRisk * tally.lethalRiskPercent
        return weights.combat * combat
    }

    /// The scored groups from best to worst value (a group's value is its best candidate's; equal
    /// values keep candidate order). Level, roll and freeze aren't simulated, so they aren't listed.
    public static func groupsByValue(
        _ candidates: [AdvisorCandidate], tallies: [String: CombatTally], weights: AdvisorWeights = .standard
    ) -> [String] {
        bestPerGroup(candidates, tallies: tallies, weights: weights).map(\.candidate.group)
    }

    /// Each scored group's best candidate, from best to worst value.
    public static func bestCandidates(
        _ candidates: [AdvisorCandidate], tallies: [String: CombatTally], weights: AdvisorWeights = .standard
    ) -> [AdvisorCandidate] {
        bestPerGroup(candidates, tallies: tallies, weights: weights).map(\.candidate)
    }

    struct Scored {
        var candidate: AdvisorCandidate
        var tally: CombatTally
        var value: Double
        var order: Int
    }

    static func bestPerGroup(
        _ candidates: [AdvisorCandidate], tallies: [String: CombatTally], weights: AdvisorWeights
    ) -> [Scored] {
        var best: [String: Scored] = [:]
        for (order, candidate) in candidates.enumerated() where candidate.action != .keep && candidate.isSimulated {
            guard let tally = tallies[candidate.id], tally.simulations > 0 else { continue }
            let scored = Scored(candidate: candidate, tally: tally, value: value(tally, weights: weights), order: order)
            if let current = best[candidate.group], (current.value, -current.order) >= (scored.value, -scored.order) { continue }
            best[candidate.group] = scored
        }
        return best.values.sorted { ($0.value, -$0.order) > ($1.value, -$1.order) }
    }

    /// Ranks the scored candidates into the advice shown: board changes that clearly improve the
    /// next combat first (by value gained), then level, freeze and roll (which fight it with the
    /// board as it is). Board changes that don't clearly help aren't shown: suggesting a sell or a
    /// buy that's about even would only be noise.
    ///
    /// - Parameter isComplete: every candidate there will be has been scored (the evaluation finished).
    public static func rank(
        _ request: AdvisorRequest, candidates: [AdvisorCandidate], tallies: [String: CombatTally],
        weights: AdvisorWeights = .standard, isComplete: Bool = true
    ) -> Advice {
        guard request.hasData else { return .noData }
        let scoredCount = candidates.filter { !$0.isSimulated || tallies[$0.id].map { $0.simulations > 0 } == true }.count
        guard let base = tallies[AdvisorAction.keep.id], base.simulations > 0 else {
            return Advice(status: .thinking, scored: 0, candidates: candidates.count)
        }
        let baseValue = value(base, weights: weights)
        let baseOdds = AdvisorOdds(base)

        struct Option {
            var candidate: AdvisorCandidate
            var tally: CombatTally
            var gain: Double
            var z: Double
            var reason: String
        }
        func option(_ scored: Scored) -> Option {
            let gain = scored.value - baseValue
            let a = scored.tally.valueStandardError(weights), b = base.valueStandardError(weights)
            let se = (a * a + b * b).squareRoot()
            return Option(
                candidate: scored.candidate, tally: scored.tally, gain: gain, z: se > 0 ? gain / se : 0,
                reason: reason(scored.tally, versus: base)
            )
        }
        let groups = bestPerGroup(candidates, tallies: tallies, weights: weights)
        let isImprovement = { (o: Option) in o.gain >= weights.minimumGain && o.z >= weights.minimumZ }
        let now = groups.filter { !$0.candidate.isForNextTurn }.map(option)
        let improvements = now.filter(isImprovement)
        let keptForNextTurn = groups.filter(\.candidate.isForNextTurn).map(option).first(where: isImprovement)

        // Level, freeze and roll: the next combat with the board as it is.
        let equity = Int(base.equity.rounded())
        var steady: [Option] = []
        for candidate in candidates where !candidate.isSimulated {
            let reason: String
            switch candidate.action {
            case .level:
                reason = improvements.isEmpty
                    ? "No buy beats your board (\(equity)% win)"
                    : "Keeps your board as it is (\(equity)% win)"
            case .freeze:
                guard let kept = keptForNextTurn else { continue }
                reason = "Saves a \(signed(kept.tally.winPercent - base.winPercent))% win buy for next turn"
            case .roll:
                guard improvements.isEmpty else { continue }
                reason = "No shop card improves your odds (\(equity)% win)"
            default:
                continue
            }
            steady.append(Option(candidate: candidate, tally: base, gain: 0, z: 0, reason: reason))
        }
        // Behind on the board: look for help first; ahead: spend on the future first.
        let steadyOrder: [String] = base.equity < 40 ? ["roll", "freeze", "level"] : ["level", "freeze", "roll"]
        steady.sort { steadyOrder.firstIndex(of: $0.candidate.group)! < steadyOrder.firstIndex(of: $1.candidate.group)! }

        let listed = Array((improvements + steady).prefix(weights.suggestions))
        let staleness = request.preview.opponentSeenTurn.map { request.preview.bgTurn - $0 } ?? 0
        let capped = staleness >= weights.staleAfterTurns || request.preview.opponentSource == .lastSeenBoard

        var suggestions: [AdvisorSuggestion] = []
        for (index, item) in listed.enumerated() {
            var confidence: AdvisorConfidence
            if item.candidate.isSimulated {
                confidence = item.z >= weights.highZ ? .high : item.z >= weights.mediumZ ? .medium : .low
                if !isImprovement(item) { confidence = .low }
                // A close runner-up among the improvements: at most medium.
                if index + 1 < listed.count, listed[index + 1].candidate.isSimulated, isImprovement(listed[index + 1]) {
                    let next = listed[index + 1]
                    let a = item.tally.valueStandardError(weights), b = next.tally.valueStandardError(weights)
                    let se = (a * a + b * b).squareRoot()
                    if se > 0, (item.gain - next.gain) / se < 1, confidence == .high { confidence = .medium }
                }
            } else {
                // A rule of thumb on top of the combat: medium only when nothing on the board helps
                // and every candidate has been scored.
                confidence = index == 0 && improvements.isEmpty && isComplete ? .medium : .low
            }
            if item.tally.simulations < weights.minimumSimulations { confidence = .low }
            if capped, confidence == .high { confidence = .medium }
            suggestions.append(AdvisorSuggestion(
                rank: index + 1, action: item.candidate.action, targets: item.candidate.action.targets,
                reason: item.reason, confidence: confidence,
                odds: AdvisorOdds(item.tally), gain: AdvisorOdds.rounded(item.gain),
                terms: AdvisorTerms(combat: AdvisorOdds.rounded(item.gain))
            ))
        }

        // The best two board changes within noise of each other: neither stands out.
        var runnerUpIsClose = false
        if listed.count >= 2, listed[0].candidate.isSimulated, listed[1].candidate.isSimulated, isImprovement(listed[1]) {
            let a = listed[0].tally.valueStandardError(weights), b = listed[1].tally.valueStandardError(weights)
            let gap = listed[0].gain - listed[1].gain, se = (a * a + b * b).squareRoot()
            runnerUpIsClose = gap < weights.minimumGain || (se > 0 && gap / se < 1)
        }

        var status = Advice.Status.recommendation
        var note: String?
        if runnerUpIsClose {
            status = .noStrongRecommendation
            note = "Options are close"
        } else if let top = suggestions.first, top.confidence != .low {
            if capped, let seen = request.preview.opponentSeenTurn { note = "Their board is from turn \(seen)" }
        } else {
            status = .noStrongRecommendation
            if suggestions.isEmpty {
                note = "Nothing to suggest"
            } else if listed[0].tally.simulations < weights.minimumSimulations {
                note = "Too few simulations yet"
            } else if improvements.count >= 2, listed[0].gain - listed[1].gain < weights.minimumGain {
                note = "Options are close"
            } else if improvements.isEmpty {
                note = "Nothing clearly improves your odds"
            } else {
                note = "Options are close"
            }
        }
        return Advice(
            status: status, note: note, baseline: baseOdds, suggestions: suggestions, scored: scoredCount,
            candidates: candidates.count
        )
    }

    /// One line on what a board change does to the next combat.
    static func reason(_ tally: CombatTally, versus base: CombatTally) -> String {
        let lethalBefore = base.lethalRiskPercent, lethalAfter = tally.lethalRiskPercent
        if lethalBefore - lethalAfter >= 5 {
            return "Cuts lethal risk \(Int(lethalBefore.rounded()))% → \(Int(lethalAfter.rounded()))%"
        }
        let win = tally.winPercent - base.winPercent
        if abs(win) >= 1 { return "\(signed(win))% win vs next opponent" }
        let taken = base.averageDamageTaken - tally.averageDamageTaken
        let dealt = tally.averageDamageDealt - base.averageDamageDealt
        if taken >= 1, taken >= abs(dealt) { return "Takes \(Int(taken.rounded())) less damage vs next opponent" }
        if dealt >= 1 { return "Deals \(Int(dealt.rounded())) more damage to next opponent" }
        if taken <= -1 { return "Takes \(Int((-taken).rounded())) more damage vs next opponent" }
        if dealt <= -1 { return "Deals \(Int((-dealt).rounded())) less damage to next opponent" }
        return "About even vs next opponent"
    }

    static func signed(_ value: Double) -> String {
        let n = Int(value.rounded())
        return n > 0 ? "+\(n)" : "\(n)"
    }
}
