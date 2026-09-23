import Foundation
import HSData

/// How well a set of cards matches one build.
public struct BuildMatch: Hashable, Sendable {
    public var build: BuildDefinition
    /// The build's core cards that are there, in the build's order.
    public var core: [String]
    /// The build's add-on cards that are there.
    public var addons: [String]
    /// This evaluation's evidence: 3 per core card, 1 more for a core card no other build has,
    /// 1 per add-on.
    public var evidence: Double
    /// What selection uses: the evidence, or what's carried over from earlier turns when that's more.
    public var score: Double

    /// Core cards not there yet.
    public var missingCore: [String] { build.core.filter { !core.contains($0) } }
}

/// What the detector looks at.
public struct BuildInput: Hashable, Sendable {
    /// Card IDs of the minions on the board and the cards in hand, plus the trinkets.
    /// Goldens are fine; duplicates count once.
    public var cardIDs: [String]
    public var bgTurn: Int
    /// Tribes known not to be in the lobby: builds for them are never detected.
    public var absentTribes: Set<HS.Race>
    /// The lobby's Deity, when known: builds that need a different one are never detected.
    public var deityDbfID: Int?

    public init(cardIDs: [String], bgTurn: Int, absentTribes: Set<HS.Race> = [], deityDbfID: Int? = nil) {
        self.cardIDs = cardIDs
        self.bgTurn = bgTurn
        self.absentTribes = absentTribes
        self.deityDbfID = deityDbfID
    }
}

/// Finds the one or two builds a player is leaning into, from their board, hand and trinkets.
///
/// Stable turn to turn by design:
/// - **Turn peaks.** Within a turn a build's score is its best evidence so far this turn
///   while any of its cards are still there, so moving, selling and rebuying cards mid-turn
///   doesn't make it flicker.
/// - **Carry-over.** Each turn's best carries into later turns, decaying by `carryDecay` per
///   turn, so selling a core card for a triple or a thin board doesn't drop the build at once.
/// - **Incumbency.** A shown build keeps its place until another beats it by `switchMargin`.
///
/// A build needs `threshold` evidence to be shown: one core card no other build has, a
/// shared core card with an add-on, two core cards, or four add-ons.
public struct BuildDetector: Sendable {
    public let catalog: BuildCatalog
    public static let threshold = 4.0
    public static let carryDecay = 0.75
    public static let switchMargin = 2.0
    /// A second build is shown when it scores at least this share of the first.
    public static let secondShare = 0.6
    /// …and keeps its place while it scores at least this share.
    public static let keepSecondShare = 0.45

    /// Core cards that only one build has.
    private let signatureCards: Set<String>
    private var turn = 0
    /// This turn's best evidence per build ID.
    private var turnPeak: [String: Double] = [:]
    /// What earlier turns carry into this one, per build ID.
    private var carry: [String: Double] = [:]
    /// The builds shown, in order.
    public private(set) var current: [String] = []

    public init(catalog: BuildCatalog) {
        self.catalog = catalog
        var coreCount: [String: Int] = [:]
        for build in catalog.builds {
            for card in Set(build.core) { coreCount[card, default: 0] += 1 }
        }
        signatureCards = Set(coreCount.filter { $0.value == 1 }.keys)
    }

    /// How well `cardIDs` match `build`, without any history.
    public func match(_ build: BuildDefinition, cards: Set<String>) -> BuildMatch {
        let core = build.core.filter(cards.contains)
        let addons = build.addons.filter(cards.contains)
        let evidence = Double(core.count) * 3 + Double(core.filter(signatureCards.contains).count)
            + Double(addons.count)
        return BuildMatch(build: build, core: core, addons: addons, evidence: evidence, score: evidence)
    }

    /// The build a board most looks like, such as an opponent's last-seen board; nil when
    /// no build has enough evidence. Ties go to the build with the better average placement.
    public func likelyBuild(cardIDs: [String], absentTribes: Set<HS.Race> = [], deityDbfID: Int? = nil) -> BuildMatch? {
        let cards = Set(cardIDs.map(catalog.baseCardID))
        return catalog.builds.filter { isPossible($0, absentTribes: absentTribes, deityDbfID: deityDbfID) }
            .map { match($0, cards: cards) }
            .filter { $0.evidence >= Self.threshold }
            .max { rank($0) < rank($1) }
    }

    /// Updates the detection with the player's cards now; returns the builds to show (0-2).
    public mutating func update(_ input: BuildInput) -> [BuildMatch] {
        if input.bgTurn != turn {
            let turns = Double(max(1, input.bgTurn - turn))
            var next: [String: Double] = [:]
            for id in Set(carry.keys).union(turnPeak.keys) {
                let value = max(carry[id] ?? 0, turnPeak[id] ?? 0) * pow(Self.carryDecay, turns)
                if value >= 0.5 { next[id] = value }
            }
            carry = input.bgTurn > turn ? next : [:]
            turnPeak = [:]
            turn = input.bgTurn
        }
        let cards = Set(input.cardIDs.map(catalog.baseCardID))
        var candidates: [String: BuildMatch] = [:]
        for build in catalog.builds where isPossible(build, absentTribes: input.absentTribes, deityDbfID: input.deityDbfID) {
            var match = match(build, cards: cards)
            if match.evidence > 0 { turnPeak[build.id] = max(turnPeak[build.id] ?? 0, match.evidence) }
            // Within a turn a build's score doesn't drop while any of its cards are still
            // there: moving, selling to triple and rebuying are part of a turn. Between turns
            // it decays from the turn's best.
            match.score = max(match.evidence > 0 ? turnPeak[build.id] ?? 0 : 0, carry[build.id] ?? 0)
            if match.score >= Self.threshold { candidates[build.id] = match }
        }
        current = select(candidates)
        return current.compactMap { candidates[$0] }
    }

    /// Forgets the game (a new game started).
    public mutating func reset() {
        turn = 0
        turnPeak = [:]
        carry = [:]
        current = []
    }

    private func select(_ candidates: [String: BuildMatch]) -> [String] {
        let ranked = candidates.values.sorted { rank($0) > rank($1) }
        guard let best = ranked.first else { return [] }
        // The first place: the incumbent unless beaten by the margin.
        var first = best
        if let incumbent = current.first.flatMap({ candidates[$0] }), best.build.id != incumbent.build.id,
           best.score < incumbent.score + Self.switchMargin {
            first = incumbent
        }
        // The old second can take over first place only by the margin too, handled above
        // because it's in `ranked` like any other challenger.
        let rest = ranked.filter { $0.build.id != first.build.id }
        var second: BuildMatch?
        if let incumbent = current.dropFirst().first.flatMap({ candidates[$0] }), incumbent.build.id != first.build.id,
           incumbent.score >= first.score * Self.keepSecondShare {
            second = incumbent
            if let challenger = rest.first, challenger.build.id != incumbent.build.id,
               challenger.score >= incumbent.score + Self.switchMargin {
                second = challenger
            }
        } else if let challenger = rest.first, challenger.score >= first.score * Self.secondShare {
            second = challenger
        }
        return [first.build.id] + (second.map { [$0.build.id] } ?? [])
    }

    /// Higher is better: score, then the better average placement, then the ID (for determinism).
    private func rank(_ match: BuildMatch) -> BuildRank {
        BuildRank(score: match.score, placement: -(match.build.averagePlacement ?? 9), id: match.build.id)
    }

    private func isPossible(_ build: BuildDefinition, absentTribes: Set<HS.Race>, deityDbfID: Int?) -> Bool {
        if !build.tribes.isEmpty, build.tribes.allSatisfy(absentTribes.contains) { return false }
        if let needed = build.requiresDeityDbfID, let deityDbfID, needed != deityDbfID { return false }
        return true
    }
}

private struct BuildRank: Comparable {
    var score: Double
    var placement: Double
    var id: String

    static func < (a: BuildRank, b: BuildRank) -> Bool {
        // Reverse ID order so that, all else equal, the alphabetically first ID ranks higher.
        (a.score, a.placement, b.id) < (b.score, b.placement, a.id)
    }
}

/// How a shop card fits the detected builds.
public enum ShopCardRole: String, Codable, Hashable, Sendable {
    /// A core card of a detected build.
    case core
    /// An add-on of a detected build.
    case addon
}

/// A shop card to highlight.
public struct ShopHighlight: Hashable, Sendable {
    /// The card's place in the shop, 0 = leftmost.
    public var index: Int
    public var cardID: String
    public var role: ShopCardRole
    /// The detected build it fits (the first one when it fits both).
    public var buildID: String
}

public enum ShopHighlighter {
    /// The shop cards that are core or add-on cards of the detected builds. Core wins over
    /// add-on; the earlier build wins a tie.
    public static func highlights(shop cardIDs: [String], builds: [BuildMatch], catalog: BuildCatalog) -> [ShopHighlight] {
        cardIDs.enumerated().compactMap { index, cardID in
            let base = catalog.baseCardID(cardID)
            if let build = builds.first(where: { $0.build.core.contains(base) }) {
                return ShopHighlight(index: index, cardID: cardID, role: .core, buildID: build.build.id)
            }
            if let build = builds.first(where: { $0.build.addons.contains(base) }) {
                return ShopHighlight(index: index, cardID: cardID, role: .addon, buildID: build.build.id)
            }
            return nil
        }
    }
}
