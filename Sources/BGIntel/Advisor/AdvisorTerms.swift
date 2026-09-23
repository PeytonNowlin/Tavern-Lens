import Foundation

// The blended score's terms besides the next combat: strength against the rest of the lobby,
// progress toward the detected builds, and the economy (gold and levelling tempo, 1-2 turns
// ahead). Each is in the combat term's unit, percentage points of win equity, so the weights
// (`AdvisorWeights.lobby`, `.build`, `.economy`) blend like with like. See
// docs/advisor/scoring.md for the model and how to tune it.

// MARK: - Lobby

extension Advisor {
    /// How much one lobby opponent counts in the lobby term: how likely they're faced soon
    /// (the one fought last turn is less likely again) times how fresh their board is (half
    /// weight every `lobbyStaleHalfLife` turns after the first).
    public static func lobbyWeight(_ opponent: AdvisorLobbyOpponent, bgTurn: Int, weights: AdvisorWeights) -> Double {
        let age = max(1, bgTurn - opponent.seenTurn)
        let likelihood = age <= 1 ? weights.lobbyRecentFactor : 1
        let freshness = pow(0.5, Double(age - 1) / max(weights.lobbyStaleHalfLife, 0.1))
        return likelihood * freshness
    }

    /// The lobby's other opponents the lobby term fights: every one with a last-seen board, by PlayerID.
    public static func lobbyOpponents(for request: AdvisorRequest) -> [AdvisorLobbyOpponent] {
        (request.lobby ?? [])
            .filter { $0.playerID != request.preview.opponentPlayerID && $0.side.player.hpLeft > 0 }
            .sorted { $0.playerID < $1.playerID }
    }

    /// A candidate's lobby gain over keeping the board, and its standard error: the weighted mean,
    /// over the opponents both were scored against, of the difference in (unweighted) combat
    /// value. Nil when there's no opponent both were scored against.
    static func lobbyGain(
        _ tallies: [Int: CombatTally]?, base: [Int: CombatTally]?, request: AdvisorRequest, weights: AdvisorWeights
    ) -> (gain: Double, se: Double)? {
        guard let tallies, let base else { return nil }
        var total = 0.0, weightSum = 0.0, variance = 0.0
        var unit = weights
        unit.combat = 1
        var parts: [(w: Double, gain: Double, se: Double)] = []
        for opponent in lobbyOpponents(for: request) {
            guard let t = tallies[opponent.playerID], let b = base[opponent.playerID], t.simulations > 0, b.simulations > 0
            else { continue }
            let w = lobbyWeight(opponent, bgTurn: request.preview.bgTurn, weights: weights)
            let se = hypot(t.valueStandardError(unit), b.valueStandardError(unit))
            parts.append((w, value(t, weights: unit) - value(b, weights: unit), se))
            weightSum += w
        }
        guard weightSum > 0 else { return nil }
        for part in parts {
            total += part.w * part.gain
            variance += (part.w / weightSum) * (part.w / weightSum) * part.se * part.se
        }
        return (weights.lobby * total / weightSum, weights.lobby * variance.squareRoot())
    }
}

// MARK: - Builds

/// Progress toward the detected builds, as the build term counts it.
public struct AdvisorBuildProgress: Sendable {
    public let request: AdvisorRequest
    public let weights: AdvisorWeights

    public init(request: AdvisorRequest, weights: AdvisorWeights) {
        self.request = request
        self.weights = weights
    }

    var builds: [AdvisorBuild] { request.builds ?? [] }

    /// The value of holding `cards` (card IDs on the board and in hand): per build, by its share,
    /// `buildCoreCard` for each core card and `buildAddonCard` for each add-on held, plus
    /// `buildCopy` for each extra copy of one toward a triple (at most two; a golden is done).
    public func value(of cards: [String]) -> Double {
        guard !builds.isEmpty else { return 0 }
        var copies: [String: Int] = [:]
        var golden: Set<String> = []
        for card in cards {
            let base = request.baseCardID(card)
            copies[base, default: 0] += 1
            if base != card { golden.insert(base) }
        }
        var total = 0.0
        for build in builds {
            var score = 0.0
            for (card, perCard) in [(build.core, weights.buildCoreCard), (build.addons, weights.buildAddonCard)]
                .flatMap({ list, value in list.map { ($0, value) } }) {
                guard let count = copies[card] else { continue }
                score += perCard
                if !golden.contains(card) { score += weights.buildCopy * Double(min(count - 1, 2)) }
            }
            total += build.share * score
        }
        return total
    }

    /// The cards held now: the board and the hand.
    var held: [String] { request.board.map(\.cardID) + request.hand.map(\.cardID) }

    /// What an action does to the build value (0 for actions that don't change the cards held).
    public func gain(_ action: AdvisorAction) -> Double {
        guard !builds.isEmpty else { return 0 }
        var cards = held
        switch action {
        case .buy(let shop, let card, _):
            guard request.shop.indices.contains(shop) else { return 0 }
            cards.append(card)
        case .sell(let board, _):
            guard request.board.indices.contains(board) else { return 0 }
            cards.remove(at: board)
        case .swap(let shop, let card, let sell, _):
            guard request.shop.indices.contains(shop), request.board.indices.contains(sell) else { return 0 }
            cards.remove(at: sell)
            cards.append(card)
        case .level(_, let tier):
            return unlockValue(tier: tier)
        default:
            return 0
        }
        return value(of: cards) - value(of: held)
    }

    /// Levelling to `tier` opens it: `buildUnlock` per build (by share) with a missing core card of that tier.
    func unlockValue(tier: Int) -> Double {
        unlockedBuilds(tier: tier).reduce(0) { $0 + $1.share * weights.buildUnlock }
    }

    /// The builds with a missing core card of `tier`.
    func unlockedBuilds(tier: Int) -> [AdvisorBuild] {
        let have = Set(held.map(request.baseCardID))
        return builds.filter { build in build.core.contains { !have.contains($0) && build.coreTiers[$0] == tier } }
    }

    /// The build a card is core for (the first one), if any.
    public func coreBuild(of cardID: String) -> AdvisorBuild? {
        let base = request.baseCardID(cardID)
        return builds.first { $0.core.contains(base) }
    }

    /// The build a card is an add-on for (the first one), if any.
    public func addonBuild(of cardID: String) -> AdvisorBuild? {
        let base = request.baseCardID(cardID)
        return builds.first { $0.addons.contains(base) }
    }
}

// MARK: - Economy

/// Gold and levelling tempo over this turn and the next two: whether levelling now beats
/// levelling next turn, in two turns or not at all, and what spending gold now does to that.
///
/// A plan "level in k turns" (k = 0, 1, 2) is worth `tierTurnValue × urgency × (3 − k)` (the
/// shops of the horizon at the higher tier) minus `goldValue ×` its price then (the upgrade
/// gets 1 cheaper each turn); it needs that much gold then. Not levelling is worth 0. Urgency
/// comes from a standard levelling curve: behind it 1.5, on it 1, ahead of it 0.5.
public struct AdvisorEconomy: Sendable {
    public let request: AdvisorRequest
    public let weights: AdvisorWeights

    public init(request: AdvisorRequest, weights: AdvisorWeights) {
        self.request = request
        self.weights = weights
    }

    /// The tier a steady levelling curve has by the end of a turn's shopping: tier 2 on turn 2,
    /// 3 on turn 5, 4 on turn 7, 5 on turn 9 and 6 from turn 11.
    public static func curveTier(turn: Int) -> Int {
        switch turn {
        case ...1: 1
        case 2...4: 2
        case 5...6: 3
        case 7...8: 4
        case 9...10: 5
        default: 6
        }
    }

    var turn: Int { request.preview.bgTurn }

    /// How much being a tier higher is worth now, from the curve.
    public var urgency: Double {
        let curve = Self.curveTier(turn: turn)
        return request.tier < curve ? 1.5 : request.tier == curve ? 1 : 0.5
    }

    /// Gold `k` turns from now (k ≥ 1): the income grows by 1 a turn up to the cap.
    func gold(inTurns k: Int) -> Int {
        let cap = request.goldCap ?? 10
        let income = request.income ?? min(cap, turn + 2)
        return min(cap, income + k)
    }

    /// The value of levelling in `k` turns (0 = now, with `gold` to spend), or nil when it can't
    /// be paid for then.
    func plan(inTurns k: Int, gold: Int) -> Double? {
        guard let cost = request.levelCost else { return nil }
        let price = max(0, cost - k)
        guard (k == 0 ? gold : self.gold(inTurns: k)) >= price else { return nil }
        return weights.tierTurnValue * urgency * Double(3 - k) - weights.goldValue * Double(price)
    }

    /// The best of levelling next turn, in two turns or not at all (0).
    var bestLater: Double { [1, 2].compactMap { plan(inTurns: $0, gold: 0) }.reduce(0, max) }

    /// Levelling now against the best later plan, with `gold` to spend now (negative when waiting
    /// is better); nil when levelling now can't be paid for (or there's no upgrade).
    func levelNow(gold: Int) -> Double? { plan(inTurns: 0, gold: gold).map { $0 - bestLater } }

    /// How much better levelling now is than waiting, with `gold` to spend now: 0 when waiting is
    /// better, nil when levelling now can't be paid for.
    public func levelNowAdvantage(gold: Int) -> Double? { levelNow(gold: gold).map { max(0, $0) } }

    /// Levelling now against the best later plan (negative when waiting is better).
    public var levelGain: Double { levelNow(gold: request.gold) ?? 0 }

    /// The gold an action spends now (negative for a sale); 0 for level, freeze and moves.
    public func spend(_ action: AdvisorAction) -> Int {
        let price = { (card: AdvisorCard) in card.cost ?? AdvisorRequest.defaultMinionCost }
        switch action {
        case .buy(let shop, _, _): return request.shop.indices.contains(shop) ? price(request.shop[shop]) : 0
        case .swap(let shop, _, _, _):
            return request.shop.indices.contains(shop) ? price(request.shop[shop]) - AdvisorRequest.sellValue : 0
        case .sell: return -AdvisorRequest.sellValue
        case .cast(let from, let index, _, _, _, _):
            return from == .shop && request.shop.indices.contains(index) ? price(request.shop[index]) : 0
        case .roll(let cost): return cost
        default: return 0
        }
    }

    /// What an action does to levelling tempo: spending the gold that would level now, when
    /// levelling now is the best plan, costs that plan's advantage; a sale that makes levelling
    /// affordable now gains it. Level itself is `levelGain`.
    public func tempo(_ action: AdvisorAction) -> Double {
        if case .level = action { return levelGain }
        let before = request.gold, after = request.gold - spend(action)
        let canBefore = levelNowAdvantage(gold: before) != nil, canAfter = levelNowAdvantage(gold: after) != nil
        if canBefore, !canAfter { return -(levelNowAdvantage(gold: before) ?? 0) }
        if !canBefore, canAfter { return levelNowAdvantage(gold: after) ?? 0 }
        return 0
    }

    /// How much a fresh shop is needed: the chance of losing the next combat as the board is.
    static func need(baseEquity: Double) -> Double { min(1, max(0, 1 - baseEquity / 100)) }

    /// A refresh: a fresh shop's worth when behind (`freshShopValue × need`), minus its gold,
    /// plus what spending it does to levelling.
    public func roll(cost: Int, baseEquity: Double) -> Double {
        weights.freshShopValue * Self.need(baseEquity: baseEquity) - weights.goldValue * Double(cost)
            + tempo(.roll(cost: cost))
    }

    /// A freeze: `freezeShare` of what the kept shop is worth next turn (`kept`, the best
    /// too-dear buy's gain or the best build card's), less the fresh shop it gives up.
    public func freeze(kept: Double, baseEquity: Double) -> Double {
        weights.freezeShare * (kept - weights.freshShopValue * Self.need(baseEquity: baseEquity))
    }
}
