import Foundation

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

/// How candidates are valued and when a suggestion counts as confident: the blend of the four
/// terms (the next combat, the rest of the lobby, build progress, economy), the heuristic terms'
/// constants, the sanity layer's thresholds and the confidence rules. Configurable and Codable,
/// so weights can be tuned by replaying the bookmarked cases under new ones (`AdvisorTuning` in
/// TavernEngine, `scripts/advisor-tune.sh`). Every value is in percentage points of win equity
/// against the next opponent (the combat term's unit) unless it says otherwise.
public struct AdvisorWeights: Codable, Hashable, Sendable {
    // MARK: Blend

    /// The weight of the combat term (the next combat against the next opponent's last-seen board).
    public var combat = 1.0
    /// The weight of the lobby term (the same board against the other opponents' last-seen boards).
    public var lobby = 0.5
    /// The weight of the build term (progress toward the detected builds).
    public var build = 1.0
    /// The weight of the economy term (gold and levelling tempo over the next two turns).
    public var economy = 1.0

    // MARK: Combat value

    /// Value per hero health of expected damage taken (a loss that costs 5 health less is worth 5
    /// points) and dealt (worth less: it only hurts one opponent).
    public var damageTakenPerHealth = 1.0
    public var damageDealtPerHealth = 0.5
    /// Value lost per percentage point of risk that the combat kills the player (on top of the loss).
    public var lethalRisk = 1.0

    // MARK: Lobby

    /// A lobby opponent's board counts half as much every this many turns after the first.
    public var lobbyStaleHalfLife = 3.0
    /// How much the opponent fought last turn counts (less likely to be faced again soon).
    public var lobbyRecentFactor = 0.5

    // MARK: Builds

    /// Holding a core card, an add-on, and each extra copy toward a triple (at most two).
    public var buildCoreCard = 6.0
    public var buildAddonCard = 2.0
    public var buildCopy = 1.5
    /// Levelling to the tier of a missing core card.
    public var buildUnlock = 3.0

    // MARK: Economy

    /// Value of one gold spent on levelling instead of the board.
    public var goldValue = 1.0
    /// Value of one turn's shops a tier higher (scaled by how far behind the levelling curve).
    public var tierTurnValue = 5.0
    /// Value of a fresh shop when the board is sure to lose (scaled by the chance of losing).
    public var freshShopValue = 6.0
    /// The share of a kept shop's value a freeze is worth (a new shop might hold better).
    public var freezeShare = 0.5

    // MARK: Sanity layer

    /// `survivalFirst` applies from this lethal risk (percent) with the board as it is.
    public var sanitySurvivalLethal = 20.0
    /// `newLethalRisk` vetoes a rise of this many points; `survivalFirst` counts a cut of this many.
    public var sanityLethalIncrease = 5.0
    /// `keepPairs` and `keepBuildCore` let a sale through when the combat gains this much.
    public var sanityOverrideGain = 15.0

    // MARK: Confidence

    /// A suggestion counts as an improvement when it gains at least this much value…
    public var minimumGain = 1.0
    /// …and this many standard errors of the simulated part of the difference.
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

    /// Only the next combat, as #19 scored it (for comparisons).
    public static var combatOnly: AdvisorWeights {
        var weights = AdvisorWeights()
        weights.lobby = 0
        weights.build = 0
        weights.economy = 0
        return weights
    }

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case combat, lobby, build, economy, damageTakenPerHealth, damageDealtPerHealth, lethalRisk
        case lobbyStaleHalfLife, lobbyRecentFactor, buildCoreCard, buildAddonCard, buildCopy, buildUnlock
        case goldValue, tierTurnValue, freshShopValue, freezeShare
        case sanitySurvivalLethal, sanityLethalIncrease, sanityOverrideGain
        case minimumGain, minimumZ, highZ, mediumZ, staleAfterTurns, minimumSimulations, suggestions
    }

    /// Weights missing from saved advice or a tuning file take today's defaults, so saved records
    /// keep loading as weights are added and a tuning file need only list what it changes.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try c.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        let d = AdvisorWeights()
        combat = try value(.combat, d.combat)
        lobby = try value(.lobby, d.lobby)
        build = try value(.build, d.build)
        economy = try value(.economy, d.economy)
        damageTakenPerHealth = try value(.damageTakenPerHealth, d.damageTakenPerHealth)
        damageDealtPerHealth = try value(.damageDealtPerHealth, d.damageDealtPerHealth)
        lethalRisk = try value(.lethalRisk, d.lethalRisk)
        lobbyStaleHalfLife = try value(.lobbyStaleHalfLife, d.lobbyStaleHalfLife)
        lobbyRecentFactor = try value(.lobbyRecentFactor, d.lobbyRecentFactor)
        buildCoreCard = try value(.buildCoreCard, d.buildCoreCard)
        buildAddonCard = try value(.buildAddonCard, d.buildAddonCard)
        buildCopy = try value(.buildCopy, d.buildCopy)
        buildUnlock = try value(.buildUnlock, d.buildUnlock)
        goldValue = try value(.goldValue, d.goldValue)
        tierTurnValue = try value(.tierTurnValue, d.tierTurnValue)
        freshShopValue = try value(.freshShopValue, d.freshShopValue)
        freezeShare = try value(.freezeShare, d.freezeShare)
        sanitySurvivalLethal = try value(.sanitySurvivalLethal, d.sanitySurvivalLethal)
        sanityLethalIncrease = try value(.sanityLethalIncrease, d.sanityLethalIncrease)
        sanityOverrideGain = try value(.sanityOverrideGain, d.sanityOverrideGain)
        minimumGain = try value(.minimumGain, d.minimumGain)
        minimumZ = try value(.minimumZ, d.minimumZ)
        highZ = try value(.highZ, d.highZ)
        mediumZ = try value(.mediumZ, d.mediumZ)
        staleAfterTurns = try value(.staleAfterTurns, d.staleAfterTurns)
        minimumSimulations = try value(.minimumSimulations, d.minimumSimulations)
        suggestions = try value(.suggestions, d.suggestions)
    }
}

/// The parts of a suggestion's value over keeping the board, each already weighted (the gain is
/// their sum). Nil where a term doesn't apply: `lobby` when the suggestion wasn't scored against
/// the rest of the lobby (no other opponent seen, or not among the best), `build` without
/// detected builds.
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

    public var total: Double { combat + (lobby ?? 0) + (build ?? 0) + (economy ?? 0) }
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

    public init(
        won: Double, tied: Double, lost: Double, lethalRisk: Double, averageDamageDealt: Double,
        averageDamageTaken: Double, simulations: Int
    ) {
        self.won = won
        self.tied = tied
        self.lost = lost
        self.lethalRisk = lethalRisk
        self.averageDamageDealt = averageDamageDealt
        self.averageDamageTaken = averageDamageTaken
        self.simulations = simulations
    }

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
    /// The value gained over keeping the board: the sum of `terms`.
    public var gain: Double
    public var terms: AdvisorTerms

    public init(
        rank: Int, action: AdvisorAction, targets: [AdvisorTarget], reason: String, confidence: AdvisorConfidence,
        odds: AdvisorOdds?, gain: Double, terms: AdvisorTerms
    ) {
        self.rank = rank
        self.action = action
        self.targets = targets
        self.reason = reason
        self.confidence = confidence
        self.odds = odds
        self.gain = gain
        self.terms = terms
    }
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
    /// The sanity rules that took out or moved down a suggestion the score would have listed
    /// (nil when none did).
    public var sanity: [AdvisorSanityNote]?

    public init(
        status: Status, note: String? = nil, baseline: AdvisorOdds? = nil, suggestions: [AdvisorSuggestion] = [],
        scored: Int = 0, candidates: Int = 0, sanity: [AdvisorSanityNote]? = nil
    ) {
        self.status = status
        self.note = note
        self.baseline = baseline
        self.suggestions = suggestions
        self.scored = scored
        self.candidates = candidates
        self.sanity = sanity
    }

    public static let noData = Advice(status: .noData, note: "No data: next opponent not fought yet")
}

extension Advisor {
    /// A candidate's combat value: win equity against the next opponent, adjusted for damage and
    /// lethal risk, times the combat weight.
    public static func value(_ tally: CombatTally, weights: AdvisorWeights = .standard) -> Double {
        let combat = tally.equity + weights.damageDealtPerHealth * tally.averageDamageDealt
            - weights.damageTakenPerHealth * tally.averageDamageTaken
            - weights.lethalRisk * tally.lethalRiskPercent
        return weights.combat * combat
    }

    /// The terms that need no simulation for a board change (build progress and levelling tempo),
    /// weighted; what ranks candidates before the lobby pass, on top of the combat value.
    static func heuristicValue(_ action: AdvisorAction, request: AdvisorRequest, weights: AdvisorWeights) -> Double {
        weights.build * AdvisorBuildProgress(request: request, weights: weights).gain(action)
            + weights.economy * AdvisorEconomy(request: request, weights: weights).tempo(action)
    }

    /// The scored groups from best to worst (a group's value is its best candidate's combat value
    /// plus its build and tempo terms; equal values keep candidate order). Level, roll and freeze
    /// aren't simulated, so they aren't listed.
    public static func groupsByValue(
        _ request: AdvisorRequest, _ candidates: [AdvisorCandidate], tallies: [String: CombatTally],
        weights: AdvisorWeights = .standard
    ) -> [String] {
        bestPerGroup(request, candidates, tallies: tallies, weights: weights).map(\.candidate.group)
    }

    /// Each scored group's best candidate, from best to worst (as `groupsByValue`).
    public static func bestCandidates(
        _ request: AdvisorRequest, _ candidates: [AdvisorCandidate], tallies: [String: CombatTally],
        weights: AdvisorWeights = .standard
    ) -> [AdvisorCandidate] {
        bestPerGroup(request, candidates, tallies: tallies, weights: weights).map(\.candidate)
    }

    struct Scored {
        var candidate: AdvisorCandidate
        var tally: CombatTally
        /// The combat value alone.
        var value: Double
        /// With the build and tempo terms.
        var blended: Double
        var order: Int
    }

    static func bestPerGroup(
        _ request: AdvisorRequest, _ candidates: [AdvisorCandidate], tallies: [String: CombatTally],
        weights: AdvisorWeights
    ) -> [Scored] {
        var best: [String: Scored] = [:]
        for (order, candidate) in candidates.enumerated() where candidate.action != .keep && candidate.isSimulated {
            guard let tally = tallies[candidate.id], tally.simulations > 0 else { continue }
            let combat = value(tally, weights: weights)
            let scored = Scored(
                candidate: candidate, tally: tally, value: combat,
                blended: combat + heuristicValue(candidate.action, request: request, weights: weights), order: order
            )
            if let current = best[candidate.group], (current.blended, -current.order) >= (scored.blended, -scored.order) { continue }
            best[candidate.group] = scored
        }
        return best.values.sorted { ($0.blended, -$0.order) > ($1.blended, -$1.order) }
    }

    /// One listed option: a candidate, its terms and why.
    struct Option {
        var candidate: AdvisorCandidate
        var order: Int
        /// Its next combat (the baseline's for level, roll and freeze).
        var tally: CombatTally
        var terms: AdvisorTerms
        /// The standard error of the simulated part of the gain (combat and lobby); 0 for level,
        /// roll and freeze, whose terms are rules of thumb.
        var se: Double
        var reason: String

        var gain: Double { terms.total }
        var z: Double { se > 0 ? gain / se : .infinity }
        /// The share of the gain from the terms that aren't simulated (build and economy).
        var heuristicShare: Double {
            let parts = [terms.combat, terms.lobby ?? 0, terms.build ?? 0, terms.economy ?? 0].map(abs)
            let total = parts.reduce(0, +)
            return total > 0 ? (parts[2] + parts[3]) / total : 0
        }
    }

    /// Ranks the scored candidates into the advice shown.
    ///
    /// Each candidate's gain over keeping the board is the blend of four weighted terms: the next
    /// combat (simulated), the rest of the lobby (simulated for the best few; `lobby`), build
    /// progress and economy (rules of thumb, `AdvisorTerms`). Options that gain at least
    /// `minimumGain`, by `minimumZ` standard errors of the simulated part, are improvements;
    /// only improvements are shown, best first, after the sanity layer (`AdvisorSanity`) has
    /// taken out or moved down clearly bad ones. Board changes that don't clearly help aren't
    /// shown: suggesting a sell or a buy that's about even would only be noise.
    ///
    /// - Parameters:
    ///   - lobby: lobby-pass results by candidate ID, then opponent PlayerID.
    ///   - isComplete: every candidate there will be has been scored (the evaluation finished).
    public static func rank(
        _ request: AdvisorRequest, candidates: [AdvisorCandidate], tallies: [String: CombatTally],
        lobby: [String: [Int: CombatTally]] = [:], weights: AdvisorWeights = .standard, isComplete: Bool = true
    ) -> Advice {
        guard request.hasData else { return .noData }
        let scoredCount = candidates.filter { !$0.isSimulated || tallies[$0.id].map { $0.simulations > 0 } == true }.count
        guard let base = tallies[AdvisorAction.keep.id], base.simulations > 0 else {
            return Advice(status: .thinking, scored: 0, candidates: candidates.count)
        }
        let baseValue = value(base, weights: weights)
        let baseSE = base.valueStandardError(weights)
        let builds = AdvisorBuildProgress(request: request, weights: weights)
        let economy = AdvisorEconomy(request: request, weights: weights)
        let hasBuilds = !(request.builds ?? []).isEmpty
        let order = Dictionary(candidates.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })

        func isImprovement(_ o: Option) -> Bool { o.gain >= weights.minimumGain && o.z >= weights.minimumZ }

        // Board changes: the best of each group.
        let groups = bestPerGroup(request, candidates, tallies: tallies, weights: weights)
        func option(_ scored: Scored) -> Option {
            let combat = scored.value - baseValue
            let combatSE = hypot(scored.tally.valueStandardError(weights), baseSE)
            let lobbyTerm = lobbyGain(
                lobby[scored.candidate.id], base: lobby[AdvisorAction.keep.id], request: request, weights: weights
            )
            let action = scored.candidate.action
            let terms = AdvisorTerms(
                combat: combat, lobby: lobbyTerm?.gain,
                build: hasBuilds ? weights.build * builds.gain(action) : nil,
                economy: weights.economy * economy.tempo(action)
            )
            return Option(
                candidate: scored.candidate, order: scored.order, tally: scored.tally, terms: terms,
                se: hypot(combatSE, lobbyTerm?.se ?? 0), reason: ""
            )
        }
        var options = groups.filter { !$0.candidate.isForNextTurn }.map(option)

        // What a freeze keeps: the best too-dear buy that would improve the board, or the best
        // build card in the shop.
        let keptBuy = groups.filter(\.candidate.isForNextTurn).map(option).first(where: isImprovement)
        var keptBuild: (value: Double, card: String)?
        if hasBuilds {
            for (k, card) in request.shop.enumerated() where card.isMinion {
                let gain = weights.build * builds.gain(.buy(shop: k, cardID: card.cardID, place: request.board.count))
                if gain > (keptBuild?.value ?? 0) { keptBuild = (gain, card.cardID) }
            }
        }
        let kept = max(keptBuy?.gain ?? 0, keptBuild?.value ?? 0)

        // Level, roll and freeze: the next combat with the board as it is, valued by the rules of thumb.
        for candidate in candidates where !candidate.isSimulated {
            var terms = AdvisorTerms(combat: 0)
            switch candidate.action {
            case .level(_, let tier):
                terms.build = hasBuilds ? weights.build * builds.unlockValue(tier: tier) : nil
                terms.economy = weights.economy * economy.levelGain
            case .roll(let cost):
                terms.economy = weights.economy * economy.roll(cost: cost, baseEquity: base.equity)
            case .freeze:
                terms.economy = weights.economy * economy.freeze(kept: kept, baseEquity: base.equity)
            default:
                continue
            }
            options.append(Option(
                candidate: candidate, order: order[candidate.id] ?? 0, tally: base, terms: terms, se: 0, reason: ""
            ))
        }

        // Best first, then the sanity layer.
        var improvements = options.filter(isImprovement).sorted { ($0.gain, -$0.order) > ($1.gain, -$1.order) }
        let shopHasImprovement = improvements.contains { Self.isFromShop($0.candidate.action) }
        let context = AdvisorSanity.Context(
            request: request, weights: weights, baseLethalRisk: base.lethalRiskPercent,
            baseSimulations: base.simulations, shopHasImprovement: shopHasImprovement, freezeKeeps: kept
        )
        let review = AdvisorSanity.review(improvements.map {
            AdvisorSanity.Option(
                action: $0.candidate.action, combatGain: $0.terms.combat, lethalRisk: $0.tally.lethalRiskPercent,
                simulations: $0.tally.simulations
            )
        }, in: context)
        let downranked = Set(review.notes.filter { $0.effect == .downrank }.map(\.candidate))
        improvements = review.order.map { improvements[$0] }

        let listed = Array(improvements.prefix(weights.suggestions)).map { item in
            var item = item
            item.reason = reason(
                item, base: base, request: request, economy: economy, builds: builds, keptBuy: keptBuy,
                keptBuild: keptBuild
            )
            return item
        }
        let staleness = request.preview.opponentSeenTurn.map { request.preview.bgTurn - $0 } ?? 0
        let capped = staleness >= weights.staleAfterTurns || request.preview.opponentSource == .lastSeenBoard

        func isClose(_ a: Option, _ b: Option) -> Bool {
            let gap = a.gain - b.gain
            guard gap >= 0 else { return false }  // reordered by the sanity layer
            let se = hypot(a.se, b.se)
            return gap < weights.minimumGain || (se > 0 && gap / se < 1)
        }

        var suggestions: [AdvisorSuggestion] = []
        for (index, item) in listed.enumerated() {
            var confidence: AdvisorConfidence
            if item.candidate.isSimulated {
                confidence = item.z >= weights.highZ ? .high : item.z >= weights.mediumZ ? .medium : .low
                // A close runner-up: at most medium.
                if index + 1 < listed.count, isClose(item, listed[index + 1]), confidence == .high { confidence = .medium }
                // Mostly a rule of thumb: at most medium.
                if item.heuristicShare > 0.5, confidence == .high { confidence = .medium }
                if item.tally.simulations < weights.minimumSimulations { confidence = .low }
            } else {
                // A rule of thumb on top of the combat: medium once everything is scored and it
                // stands out, else low.
                confidence = isComplete && item.gain >= 2 * weights.minimumGain ? .medium : .low
                if base.simulations < weights.minimumSimulations { confidence = .low }
            }
            if downranked.contains(item.candidate.action.id) { confidence = .low }
            if capped, confidence == .high { confidence = .medium }
            suggestions.append(AdvisorSuggestion(
                rank: index + 1, action: item.candidate.action, targets: item.candidate.action.targets,
                reason: item.reason, confidence: confidence,
                odds: AdvisorOdds(item.tally), gain: AdvisorOdds.rounded(item.gain),
                terms: AdvisorTerms(
                    combat: AdvisorOdds.rounded(item.terms.combat), lobby: item.terms.lobby.map(AdvisorOdds.rounded),
                    build: item.terms.build.map(AdvisorOdds.rounded), economy: item.terms.economy.map(AdvisorOdds.rounded)
                )
            ))
        }

        var status = Advice.Status.recommendation
        var note: String?
        if listed.count >= 2, isClose(listed[0], listed[1]) {
            status = .noStrongRecommendation
            note = "Options are close"
        } else if let top = suggestions.first, top.confidence != .low {
            if capped, let seen = request.preview.opponentSeenTurn { note = "Their board is from turn \(seen)" }
        } else {
            status = .noStrongRecommendation
            if suggestions.isEmpty {
                note = "Nothing clearly improves your odds"
            } else if listed[0].tally.simulations < weights.minimumSimulations {
                note = "Too few simulations yet"
            } else {
                note = "No option stands out"
            }
        }
        return Advice(
            status: status, note: note, baseline: AdvisorOdds(base), suggestions: suggestions, scored: scoredCount,
            candidates: candidates.count, sanity: review.notes.isEmpty ? nil : review.notes
        )
    }

    static func isFromShop(_ action: AdvisorAction) -> Bool {
        switch action {
        case .buy, .swap: true
        case .cast(let from, _, _, _, _, _): from == .shop
        default: false
        }
    }

    /// One line on why: the biggest term's reason.
    static func reason(
        _ option: Option, base: CombatTally, request: AdvisorRequest, economy: AdvisorEconomy,
        builds: AdvisorBuildProgress, keptBuy: Option?, keptBuild: (value: Double, card: String)?
    ) -> String {
        let terms = option.terms
        let equity = Int(base.equity.rounded())
        switch option.candidate.action {
        case .level(let cost, let tier):
            if (terms.build ?? 0) > (terms.economy ?? 0), !builds.unlockedBuilds(tier: tier).isEmpty {
                return "Opens tier \(tier) for a core card you need"
            }
            if economy.urgency > 1 { return "Behind the levelling curve (tier \(request.tier))" }
            if economy.urgency == 1 { return "Good tempo to level (costs \(cost))" }
            return "Levelling now beats waiting"
        case .roll:
            return "No shop card helps (\(equity)% win)"
        case .freeze:
            if let keptBuy, keptBuy.gain >= (keptBuild?.value ?? 0) {
                return "Saves a \(signed(keptBuy.tally.winPercent - base.winPercent))% win buy for next turn"
            }
            if let card = keptBuild?.card {
                return builds.coreBuild(of: card) != nil ? "Keeps a core card for next turn" : "Keeps a build card for next turn"
            }
            return "Keeps the shop for next turn"
        default:
            break
        }
        let lobby = terms.lobby ?? 0, build = terms.build ?? 0, tempo = terms.economy ?? 0
        let biggest = max(lobby, build, tempo)
        if terms.combat >= biggest || biggest <= 0 { return reason(option.tally, versus: base) }
        if biggest == build, let card = boughtCard(option.candidate.action) {
            if let core = builds.coreBuild(of: card) { return "Core card for \(core.name)" }
            if let addon = builds.addonBuild(of: card) { return "Add-on for \(addon.name)" }
            return "A copy toward a triple"
        }
        if biggest == tempo { return "Frees the gold to level now" }
        if biggest == lobby { return "Stronger vs the rest of the lobby" }
        return reason(option.tally, versus: base)
    }

    static func boughtCard(_ action: AdvisorAction) -> String? {
        switch action {
        case .buy(_, let card, _), .swap(_, let card, _, _): card
        default: nil
        }
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
