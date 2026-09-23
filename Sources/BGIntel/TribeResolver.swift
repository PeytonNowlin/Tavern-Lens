import Foundation
import HSData

/// The lobby's tribes as read from the hero-pick banner (#14's screen reading).
public struct ScreenTribeReading: Codable, Hashable, Sendable {
    /// The tribes read.
    public var tribes: [HS.Race]
    /// Whether every tribe of the lobby was read (the banner lists them all), rather than only some.
    public var isComplete: Bool
    /// How sure the reader is, 0…1.
    public var confidence: Double

    public init(tribes: [HS.Race], isComplete: Bool = true, confidence: Double = 1) {
        self.tribes = tribes
        self.isComplete = isComplete
        self.confidence = confidence
    }
}

/// Where a confirm-only minion was seen.
public enum PoolMinionSighting: String, Codable, Hashable, Sendable {
    case opponentBoard
    case discover
    case generated
}

/// One piece of evidence about the lobby's tribes.
public enum TribeEvidence: Hashable, Sendable {
    /// Bob offered this minion while the local player was at `tavernTier`. Shop draws are
    /// uniform over the lobby's copies at or below the tier, so they count both ways: a
    /// lobby that explains them with a smaller pool is more likely.
    case shopDraw(cardID: String, tavernTier: Int)
    /// A pool minion seen elsewhere (opponent board, discover option, generated card). It
    /// confirms its tribe is in the lobby but, being comp-skewed, says nothing about absence.
    case poolMinion(cardID: String, seen: PoolMinionSighting)
    /// A lobby hero or hero-pick option: some heroes are offered only with (or without) a tribe.
    case hero(cardID: String)
    /// The hero-pick banner, read from the screen: the strongest evidence.
    case screen(ScreenTribeReading)
}

/// How sure the resolver is that a tribe is in the lobby.
public enum TribeConfidence: String, Codable, Hashable, Sendable {
    /// P ≥ 0.99.
    case confirmed
    /// 0.5 ≤ P < 0.99.
    case likely
    /// 0.01 < P < 0.5.
    case unlikely
    /// P ≤ 0.01.
    case absent

    init(probability p: Double) {
        self = p >= 0.99 ? .confirmed : p <= 0.01 ? .absent : p >= 0.5 ? .likely : .unlikely
    }
}

/// Where the current answer comes from.
public enum TribeSource: String, Codable, Hashable, Sendable {
    /// From the log alone: no screen reading, or one the log contradicts (`screenConflict`).
    case inferred
    case screen
    /// The screen reading and the inference agree.
    case screenAndInferred
}

public struct TribeLikelihood: Hashable, Sendable {
    public var tribe: HS.Race
    /// P(the tribe is in the lobby).
    public var probability: Double
    public var confidence: TribeConfidence
    /// Forced into every lobby this patch (such as Aberrations until about 2026-10-06).
    public var isForced: Bool
}

/// The resolver's current answer.
public struct TribeEstimate: Hashable, Sendable {
    /// Every tribe in rotation, in name order.
    public var tribes: [TribeLikelihood]
    /// Every tribe is confirmed or absent.
    public var isResolved: Bool
    /// The most likely lobby and its probability.
    public var mostLikely: [HS.Race]
    public var mostLikelyProbability: Double
    /// The evidence contradicts every lobby (pool drift or a special lobby), or no lobby
    /// stands out after BG turn 6: show "tribes: uncertain".
    public var isUncertain: Bool
    public var source: TribeSource
    /// The screen reading and the log disagree.
    public var screenConflict: Bool
    /// Evidence counted so far.
    public var shopDraws: Int
    public var confirmations: Int

    /// The lobby's tribes once resolved.
    public var lobby: [HS.Race]? { isResolved ? tribes.filter { $0.confidence == .confirmed }.map(\.tribe) : nil }
}

/// Infers the lobby's tribes with a Bayesian filter over every possible lobby
/// (docs/research/minion-pool-and-tribe-inference.md §B.2).
///
/// A lobby is the forced tribes plus `tribesPerLobby − forced` of the others in rotation
/// (126 lobbies while Aberrations are forced, 252 after). Shop draws are weighed by the
/// lobby's pool size up to the tavern tier; confirmations, heroes and screen readings
/// penalise the lobbies they rule out by a small ε, so no single piece of evidence is ever
/// fatal. The screen reading is kept apart from the log's evidence so the two can be
/// cross-checked.
public struct TribeResolver: Sendable {
    public struct Parameters: Hashable, Sendable {
        /// Copies per tier 1…6 (assumed 16/15/13/11/9/7; only the ratios matter).
        public var copiesPerTier: [Int] = [16, 15, 13, 11, 9, 7]
        /// A shop draw the lobby can't explain.
        public var shopEpsilon = 1e-3
        /// A confirm-only minion the lobby can't explain (comp and effect noise).
        public var confirmEpsilon = 0.02
        /// A hero the lobby shouldn't offer (the rules may be stale).
        public var heroEpsilon = 0.02
        /// A lobby the screen reading rules out, at full confidence (scaled by confidence).
        public var screenEpsilon = 1e-6
        /// After this BG turn a most likely lobby under 0.5 counts as uncertain.
        public var uncertainAfterTurn = 6

        public init() {}
    }

    public let pool: MinionPool
    public let parameters: Parameters
    /// Tribes in rotation; bit i of a lobby mask is `rotation[i]`.
    public let rotation: [HS.Race]
    public let forced: [HS.Race]
    private let lobbies: [UInt32]
    /// `denominators[h][t]`: the lobby's copies at tier ≤ t, t = 0…6.
    private let denominators: [[Double]]
    private var logInferred: [Double]
    private var logScreen: [Double]
    private var hasScreenReading = false
    private var contradictions = 0
    public private(set) var shopDraws = 0
    public private(set) var confirmations = 0

    /// - Parameter gameDate: when the game started, for forced tribes with an end date;
    ///   nil treats every forced tribe as forced.
    public init(pool: MinionPool, gameDate: Date?, parameters: Parameters = Parameters()) {
        self.pool = pool
        self.parameters = parameters
        let rotation = pool.tribesInRotation
        self.rotation = rotation
        let forced = pool.forcedTribes(at: gameDate).filter(rotation.contains)
        self.forced = forced
        var forcedMask: UInt32 = 0
        for tribe in forced { forcedMask |= Self.bit(tribe, in: rotation) }
        let others = rotation.indices.filter { forcedMask & (1 << $0) == 0 }
        let pick = max(0, min(others.count, pool.tribesPerLobby - forced.count))
        lobbies = Self.combinations(others, pick).map { $0.reduce(forcedMask) { $0 | (1 << $1) } }

        var denominators = Array(repeating: Array(repeating: 0.0, count: 7), count: lobbies.count)
        let minions = Array(pool.minions.values)
        let gates = minions.map { Self.mask($0.lobbyGate, in: rotation) }
        for (h, lobby) in lobbies.enumerated() {
            var perTier = Array(repeating: 0.0, count: 7)
            for (minion, gate) in zip(minions, gates) where (1...6).contains(minion.tier) && !minion.isOutOfRotation {
                if gate == 0 || gate & lobby != 0 { perTier[minion.tier] += Double(parameters.copiesPerTier[minion.tier - 1]) }
            }
            for t in 1...6 { denominators[h][t] = denominators[h][t - 1] + perTier[t] }
        }
        self.denominators = denominators
        logInferred = Array(repeating: 0, count: lobbies.count)
        logScreen = Array(repeating: 0, count: lobbies.count)
    }

    public var lobbyCount: Int { lobbies.count }

    public mutating func observe(_ evidence: TribeEvidence) {
        switch evidence {
        case .shopDraw(let cardID, let tavernTier):
            guard let minion = pool.minion(cardID) else { return }
            let tier = min(max(tavernTier, 1), 6)
            // Above the tavern tier (or tier 7) it wasn't a draw: some effect put it there.
            guard (1...6).contains(minion.tier), minion.tier <= tier, !minion.isOutOfRotation else {
                confirm(minion)
                return
            }
            shopDraws += 1
            let gate = Self.mask(minion.lobbyGate, in: rotation)
            let copies = Double(parameters.copiesPerTier[minion.tier - 1])
            let miss = log(parameters.shopEpsilon)
            for h in lobbies.indices {
                let explains = gate == 0 || gate & lobbies[h] != 0
                logInferred[h] += explains ? log(copies / denominators[h][tier]) : miss
            }
        case .poolMinion(let cardID, _):
            guard let minion = pool.minion(cardID) else { return }
            confirm(minion)
        case .hero(let cardID):
            guard let rule = pool.heroRule(cardID) else { return }
            let needs = Self.mask(rule.needsAny, in: rotation)
            let banned = Self.mask(rule.bannedWithAny, in: rotation)
            // A rule naming only tribes out of rotation says nothing here.
            if needs == 0, rule.needsAny.isEmpty == false { return }
            penalise(log(parameters.heroEpsilon), into: \.logInferred) { lobby in
                (needs != 0 && needs & lobby == 0) || banned & lobby != 0
            }
        case .screen(let reading):
            let read = Self.mask(reading.tribes, in: rotation)
            let epsilon = min(0.5, pow(parameters.screenEpsilon, min(max(reading.confidence, 0), 1)))
            hasScreenReading = true
            penalise(log(epsilon), into: \.logScreen) { lobby in
                read & lobby != read || (reading.isComplete && lobby != read)
            }
        }
    }

    /// A confirm-only minion: penalise every lobby without its tribe.
    private mutating func confirm(_ minion: PoolMinion) {
        if minion.isOutOfRotation {
            contradictions += 1
            return
        }
        let gate = Self.mask(minion.lobbyGate, in: rotation)
        guard gate != 0 else { return }
        confirmations += 1
        penalise(log(parameters.confirmEpsilon), into: \.logInferred) { gate & $0 == 0 }
    }

    private mutating func penalise(
        _ penalty: Double, into keyPath: WritableKeyPath<TribeResolver, [Double]>, where rulesOut: (UInt32) -> Bool
    ) {
        var hits = 0
        for h in lobbies.indices where rulesOut(lobbies[h]) {
            self[keyPath: keyPath][h] += penalty
            hits += 1
        }
        if hits == lobbies.count, hits > 0 { contradictions += 1 }
    }

    /// The current answer. `bgTurn` decides when a weak answer counts as uncertain.
    ///
    /// With a screen reading, the answer combines it with the log's evidence, unless the
    /// two disagree (a tribe one is sure of and the other rules out): then the reading is
    /// taken as a misread, the answer is the log's alone, and `screenConflict` says so.
    public func estimate(bgTurn: Int = 0) -> TribeEstimate {
        var source = TribeSource.inferred
        var conflict = false
        if hasScreenReading {
            let inferred: [Double] = marginals(Self.normalised(logInferred))
            let screenOnly: [Double] = marginals(Self.normalised(logScreen))
            // A tribe the screen puts in that the log rules out, or the other way round.
            for i in rotation.indices {
                let screenIn = screenOnly[i] >= 0.99, screenOut = screenOnly[i] <= 0.01
                let logIn = inferred[i] >= 0.99, logOut = inferred[i] <= 0.01
                if (screenIn && logOut) || (screenOut && logIn) { conflict = true }
            }
            let inferredResolved = inferred.allSatisfy { $0 >= 0.99 || $0 <= 0.01 }
            source = conflict ? .inferred : inferredResolved ? .screenAndInferred : .screen
        }
        let posterior = Self.normalised(conflict ? logInferred : zip(logInferred, logScreen).map(+))
        let probabilities = marginals(posterior)
        let best = posterior.indices.max { posterior[$0] < posterior[$1] }
        let tribes = rotation.indices.map { i in
            TribeLikelihood(
                tribe: rotation[i], probability: probabilities[i],
                confidence: TribeConfidence(probability: probabilities[i]),
                isForced: forced.contains(rotation[i])
            )
        }
        let resolved = !lobbies.isEmpty && tribes.allSatisfy { $0.confidence == .confirmed || $0.confidence == .absent }
        let bestProbability = best.map { posterior[$0] } ?? 0

        return TribeEstimate(
            tribes: tribes, isResolved: resolved,
            mostLikely: best.map { mask in rotation.indices.filter { lobbies[mask] & (1 << $0) != 0 }.map { rotation[$0] } } ?? [],
            mostLikelyProbability: bestProbability,
            isUncertain: contradictions > 0 || (bgTurn > parameters.uncertainAfterTurn && bestProbability < 0.5),
            source: source, screenConflict: conflict, shopDraws: shopDraws, confirmations: confirmations
        )
    }

    private func marginals(_ posterior: [Double]) -> [Double] {
        var result = Array(repeating: 0.0, count: rotation.count)
        for (h, p) in posterior.enumerated() {
            for i in rotation.indices where lobbies[h] & (1 << i) != 0 { result[i] += p }
        }
        return result.map { min(1, max(0, $0)) }
    }

    private static func normalised(_ logs: [Double]) -> [Double] {
        guard let top = logs.max() else { return [] }
        let weights = logs.map { exp($0 - top) }
        let total = weights.reduce(0, +)
        return weights.map { $0 / total }
    }

    private static func bit(_ tribe: HS.Race, in rotation: [HS.Race]) -> UInt32 {
        rotation.firstIndex(of: tribe).map { 1 << UInt32($0) } ?? 0
    }

    private static func mask(_ tribes: [HS.Race], in rotation: [HS.Race]) -> UInt32 {
        tribes.reduce(0) { $0 | bit($1, in: rotation) }
    }

    private static func combinations(_ items: [Int], _ k: Int) -> [[Int]] {
        guard k > 0 else { return [[]] }
        guard items.count >= k else { return [] }
        var result: [[Int]] = []
        for (i, first) in items.enumerated() {
            for rest in combinations(Array(items[(i + 1)...]), k - 1) { result.append([first] + rest) }
        }
        return result
    }
}
