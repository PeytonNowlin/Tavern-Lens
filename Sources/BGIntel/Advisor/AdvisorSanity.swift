import Foundation

/// The rule-based sanity layer: hand-written checks that veto or downrank clearly bad advice,
/// whatever the blended score says. The simulation can be wrong about a stale board, and the
/// heuristic terms are rough, so these catch advice a player would call a blunder.
///
/// A **veto** takes the suggestion out; a **downrank** puts it after every suggestion no rule
/// downranked. Each rule is documented here and in docs/advisor/scoring.md, and tested on
/// synthetic states and the bookmarked cases.
public enum AdvisorSanityRule: String, Codable, Hashable, Sendable, CaseIterable {
    /// Veto an action that costs more gold than there is.
    case unaffordable
    /// Veto selling the only minion: an empty board loses the combat for nothing.
    case lastMinion
    /// Veto a board change that raises the next combat's chance of killing the player by
    /// `sanityLethalIncrease` points or more (and by more than twice its noise).
    case newLethalRisk
    /// When the board as it is has at least `sanitySurvivalLethal`% risk of dying next combat,
    /// downrank levelling and freezing below every board change that cuts that risk: survive first.
    case survivalFirst
    /// Veto selling (or swapping out) one of two copies of a minion, which throws away half a
    /// triple, unless the combat gains `sanityOverrideGain` or more.
    case keepPairs
    /// Veto selling (or swapping out) a core card of a detected build, unless the combat gains
    /// `sanityOverrideGain` or more.
    case keepBuildCore
    /// Veto a refresh while the shop has a card that improves the board: buy it first.
    case rollPastImprovement
    /// Veto a freeze when nothing in the shop is worth keeping for next turn.
    case freezeForNothing

    public enum Effect: String, Codable, Hashable, Sendable {
        case veto, downrank
    }

    public var effect: Effect { self == .survivalFirst ? .downrank : .veto }

    /// One line for debugging and bookmarks.
    public var summary: String {
        switch self {
        case .unaffordable: "Costs more gold than you have"
        case .lastMinion: "Sells your only minion"
        case .newLethalRisk: "Raises the risk of dying next combat"
        case .survivalFirst: "You may die next combat: fix the board first"
        case .keepPairs: "Breaks a pair toward a triple"
        case .keepBuildCore: "Sells a core card of your build"
        case .rollPastImprovement: "The shop already has an upgrade"
        case .freezeForNothing: "Nothing in the shop is worth keeping"
        }
    }
}

/// A rule that fired on a candidate the ranking would otherwise have listed.
public struct AdvisorSanityNote: Codable, Hashable, Sendable {
    public var rule: AdvisorSanityRule
    /// The candidate's `AdvisorCandidate.id`.
    public var candidate: String
    public var effect: AdvisorSanityRule.Effect

    public init(rule: AdvisorSanityRule, candidate: String) {
        self.rule = rule
        self.candidate = candidate
        effect = rule.effect
    }
}

public enum AdvisorSanity {
    /// What the rules look at for one listed candidate.
    public struct Option: Sendable {
        public var action: AdvisorAction
        /// The combat term's gain (weighted), over keeping the board.
        public var combatGain: Double
        /// The next combat's lethal risk with the action taken, in percent, and its simulations.
        public var lethalRisk: Double
        public var simulations: Int

        public init(action: AdvisorAction, combatGain: Double, lethalRisk: Double, simulations: Int) {
            self.action = action
            self.combatGain = combatGain
            self.lethalRisk = lethalRisk
            self.simulations = simulations
        }
    }

    /// The state the options are for.
    public struct Context: Sendable {
        public var request: AdvisorRequest
        public var weights: AdvisorWeights
        /// The board as it is: its lethal risk and simulations.
        public var baseLethalRisk: Double
        public var baseSimulations: Int
        /// An improvement among the candidates is bought (or cast) from the current shop.
        public var shopHasImprovement: Bool
        /// What a freeze keeps for next turn (≤ 0: nothing worth it).
        public var freezeKeeps: Double

        public init(
            request: AdvisorRequest, weights: AdvisorWeights, baseLethalRisk: Double, baseSimulations: Int,
            shopHasImprovement: Bool, freezeKeeps: Double
        ) {
            self.request = request
            self.weights = weights
            self.baseLethalRisk = baseLethalRisk
            self.baseSimulations = baseSimulations
            self.shopHasImprovement = shopHasImprovement
            self.freezeKeeps = freezeKeeps
        }
    }

    /// The first rule that vetoes `option`, if any (downranking is `downrank`'s).
    public static func veto(_ option: Option, in context: Context) -> AdvisorSanityRule? {
        let request = context.request, weights = context.weights
        let economy = AdvisorEconomy(request: request, weights: weights)
        switch option.action {
        case .level(let cost, _): if cost > request.gold { return .unaffordable }
        default: if economy.spend(option.action) > request.gold { return .unaffordable }
        }
        if case .sell = option.action, request.board.count <= 1 { return .lastMinion }
        if option.action.changesBoard {
            let increase = option.lethalRisk - context.baseLethalRisk
            let noise = 2 * hypot(lethalSE(option.lethalRisk, option.simulations), lethalSE(context.baseLethalRisk, context.baseSimulations))
            if increase >= weights.sanityLethalIncrease, increase > noise { return .newLethalRisk }
        }
        if let sold = soldIndex(option.action), request.board.indices.contains(sold),
           option.combatGain < weights.sanityOverrideGain {
            let card = request.board[sold]
            let base = request.baseCardID(card.cardID)
            if !card.golden, base == card.cardID {
                let others = (request.board.enumerated().filter { $0.offset != sold }.map(\.element) + request.hand)
                    .filter { !$0.golden && $0.cardID == card.cardID }
                if !others.isEmpty { return .keepPairs }
            }
            if AdvisorBuildProgress(request: request, weights: weights).coreBuild(of: card.cardID) != nil {
                return .keepBuildCore
            }
        }
        if case .roll = option.action, context.shopHasImprovement { return .rollPastImprovement }
        if option.action == .freeze, context.freezeKeeps <= 0 { return .freezeForNothing }
        return nil
    }

    /// Whether `option` is downranked (`survivalFirst`): the board may die next combat, `option`
    /// is a level or freeze, and some listed board change cuts the risk.
    public static func downrank(_ option: Option, among options: [Option], in context: Context) -> AdvisorSanityRule? {
        guard context.baseLethalRisk >= context.weights.sanitySurvivalLethal else { return nil }
        switch option.action {
        case .level, .freeze:
            let helps = options.contains {
                $0.action.changesBoard && context.baseLethalRisk - $0.lethalRisk >= context.weights.sanityLethalIncrease
            }
            return helps ? .survivalFirst : nil
        default:
            return nil
        }
    }

    /// Applies the rules to options already in ranked order: vetoed ones are dropped, downranked
    /// ones move after the rest (each group keeping its order). Returns the new order (indices
    /// into `options`) and the notes of every rule that fired.
    public static func review(_ options: [Option], in context: Context) -> (order: [Int], notes: [AdvisorSanityNote]) {
        var kept: [Int] = [], later: [Int] = []
        var fired: [Int: AdvisorSanityRule] = [:]
        for (index, option) in options.enumerated() {
            if let rule = veto(option, in: context) {
                fired[index] = rule
            } else if let rule = downrank(option, among: options, in: context) {
                fired[index] = rule
                later.append(index)
            } else {
                kept.append(index)
            }
        }
        let notes = fired.keys.sorted().map { AdvisorSanityNote(rule: fired[$0]!, candidate: options[$0].action.id) }
        return (kept + later, notes)
    }

    /// The rules the shown advice breaks, judged from the advice and its request alone (the check
    /// run on every bookmarked case): the veto rules that need no other candidates, plus
    /// `rollPastImprovement` and `survivalFirst` among the suggestions shown. Empty when sane.
    public static func violations(_ advice: Advice, request: AdvisorRequest, weights: AdvisorWeights = .standard) -> [AdvisorSanityNote] {
        guard let base = advice.baseline else { return [] }
        let options = advice.suggestions.map {
            Option(action: $0.action, combatGain: $0.terms.combat, lethalRisk: $0.odds?.lethalRisk ?? base.lethalRisk,
                   simulations: $0.odds?.simulations ?? base.simulations)
        }
        let shopImprovement = advice.suggestions.contains { suggestion in
            guard suggestion.gain >= weights.minimumGain else { return false }
            switch suggestion.action {
            case .buy, .swap: return true
            case .cast(let from, _, _, _, _, _): return from == .shop
            default: return false
            }
        }
        let context = Context(
            request: request, weights: weights, baseLethalRisk: base.lethalRisk, baseSimulations: base.simulations,
            shopHasImprovement: shopImprovement, freezeKeeps: .infinity
        )
        var notes: [AdvisorSanityNote] = []
        var seenBoardChangeThatHelps = false
        for option in options {
            if let rule = veto(option, in: context) { notes.append(AdvisorSanityNote(rule: rule, candidate: option.action.id)) }
            if option.action.changesBoard, base.lethalRisk - option.lethalRisk >= weights.sanityLethalIncrease {
                seenBoardChangeThatHelps = true
            }
            // A level or freeze listed before a board change that cuts a dangerous lethal risk.
            if !seenBoardChangeThatHelps, downrank(option, among: options, in: context) != nil {
                notes.append(AdvisorSanityNote(rule: .survivalFirst, candidate: option.action.id))
            }
        }
        return notes
    }

    static func soldIndex(_ action: AdvisorAction) -> Int? {
        switch action {
        case .sell(let board, _): board
        case .swap(_, _, let sell, _): sell
        default: nil
        }
    }

    static func lethalSE(_ percent: Double, _ simulations: Int) -> Double {
        guard simulations > 0 else { return 100 }
        let p = min(max(percent / 100, 0.5 / Double(simulations)), 1 - 0.5 / Double(simulations))
        return (p * (1 - p) / Double(simulations)).squareRoot() * 100
    }
}
