/// A candidate action and the combat it leads to, for scoring.
public struct AdvisorCandidate: Codable, Hashable, Sendable {
    public var action: AdvisorAction
    /// A shop minion the player can't afford yet, scored to see whether freezing keeps something
    /// worth buying next turn. Never suggested itself.
    public var isForNextTurn: Bool
    /// The next combat with the action taken; nil when the action leaves the board as it is.
    public var input: BattleInput?

    public init(_ action: AdvisorAction, isForNextTurn: Bool = false, input: BattleInput? = nil) {
        self.action = action
        self.isForNextTurn = isForNextTurn
        self.input = input
    }

    public var id: String { (isForNextTurn ? "next:" : "") + action.id }
    public var group: String { (isForNextTurn ? "next:" : "") + action.group }
    /// Whether scoring it takes a simulation: the baseline and every board change. Level, roll and
    /// freeze fight the next combat with the board as it is, so they share the baseline's score.
    public var isSimulated: Bool { action == .keep || action.changesBoard }
}

/// The advisor: candidate actions for a recruit-phase state, and their ranking once scored.
///
/// Everything here is a pure function of the request and the scores, so the same state and the
/// same simulation results give the same advice (the replay and the golden tests rely on it).
/// Scoring itself (simulating each candidate's combat) is the caller's; see `AdvisorEvaluation`
/// in TavernEngine.
public enum Advisor {
    /// How many of the best stage-0 groups get their other placements, targets or sells tried.
    public static let refinedGroups = 3

    /// Stage 0: the baseline (the board as it is), every affordable buy played at the right end,
    /// every playable minion in hand at the right end, every sell, every modelled tavern spell on
    /// its most likely target (one per Choose One option), and when the board is full, each
    /// affordable buy in place of the weakest minion. Plus level, roll and freeze, which aren't
    /// simulated. Empty without data (the next opponent unseen).
    public static func initialCandidates(for request: AdvisorRequest) -> [AdvisorCandidate] {
        guard let base = request.preview.input else { return [] }
        let make = Hypothesis(request: request, base: base)
        let board = request.board
        var result = [AdvisorCandidate(.keep)]

        let canBuy = board.count < AdvisorRequest.boardLimit && request.hand.count < AdvisorRequest.handLimit
        for (k, card) in request.shop.enumerated() where card.isMinion && canBuy && make.price(card) <= request.gold {
            result.append(make.buy(shop: k, place: board.count))
        }
        for (h, card) in request.hand.enumerated() where card.isMinion && !card.entity.locked
            && board.count < AdvisorRequest.boardLimit {
            result.append(make.play(hand: h, place: board.count))
        }
        for i in board.indices { result.append(make.sell(board: i)) }
        if board.count >= AdvisorRequest.boardLimit, request.hand.count < AdvisorRequest.handLimit,
           let weakest = make.weakest() {
            for (k, card) in request.shop.enumerated()
            where card.isMinion && make.price(card) <= request.gold + AdvisorRequest.sellValue {
                result.append(make.swap(shop: k, sell: weakest))
            }
        }
        for spell in make.castableSpells() {
            for (option, effect) in spell.options.enumerated() {
                let target = effect.needsTarget ? make.defaultTarget(for: effect) : nil
                if effect.needsTarget, target == nil { continue }
                result.append(make.cast(spell, option: option, target: target))
            }
        }
        if let cost = request.levelCost, cost <= request.gold {
            result.append(AdvisorCandidate(.level(cost: cost, toTier: request.tier + 1)))
        }
        if let cost = request.rollCost, cost <= request.gold {
            result.append(AdvisorCandidate(.roll(cost: cost)))
        }
        if request.canFreeze, !request.shopFrozen, !request.shop.isEmpty {
            result.append(AdvisorCandidate(.freeze))
        }
        return result
    }

    /// Stage 1, once stage 0 is scored: the other placements of the best buys and plays, the other
    /// targets of the best spells, the other sells of the best swaps, moving each minion to either
    /// end, and (when freezing is possible) the shop minions too dear for now, played at the right end.
    ///
    /// - Parameter bestFirst: stage 0's groups from best to worst (`AdvisorRanking.groupsByValue`).
    public static func refinements(for request: AdvisorRequest, bestFirst: [String]) -> [AdvisorCandidate] {
        guard let base = request.preview.input else { return [] }
        let make = Hypothesis(request: request, base: base)
        let board = request.board
        let initial = Set(initialCandidates(for: request).map(\.id))
        var result: [AdvisorCandidate] = []
        func add(_ candidate: AdvisorCandidate) {
            if !initial.contains(candidate.id), !result.contains(where: { $0.id == candidate.id }) { result.append(candidate) }
        }
        let refined = bestFirst.filter { group in
            ["buy:", "play:", "cast:", "swap:"].contains { group.hasPrefix($0) }
        }.prefix(refinedGroups)
        let spells = make.castableSpells()
        for group in refined {
            if group.hasPrefix("buy:"), let k = Int(group.dropFirst("buy:s".count)) {
                for place in 0..<board.count { add(make.buy(shop: k, place: place)) }
            } else if group.hasPrefix("play:"), let h = Int(group.dropFirst("play:h".count)) {
                for place in 0..<board.count { add(make.play(hand: h, place: place)) }
            } else if group.hasPrefix("swap:"), let k = Int(group.dropFirst("swap:s".count)) {
                for sell in board.indices { add(make.swap(shop: k, sell: sell)) }
            } else if let spell = spells.first(where: { "cast:\($0.source.rawValue)\($0.index)" == group }) {
                for (option, effect) in spell.options.enumerated() where effect.needsTarget {
                    for target in board.indices { add(make.cast(spell, option: option, target: target)) }
                }
            }
        }
        if board.count >= 2 {
            for i in board.indices {
                for to in [0, board.count - 1] where to != i { add(make.move(board: i, to: to)) }
            }
        }
        if request.canFreeze, !request.shopFrozen, board.count < AdvisorRequest.boardLimit {
            for (k, card) in request.shop.enumerated() where card.isMinion && make.price(card) > request.gold {
                var candidate = make.buy(shop: k, place: board.count)
                candidate.isForNextTurn = true
                add(candidate)
            }
        }
        return result
    }
}

/// Builds hypothetical combats from the request's baseline input.
struct Hypothesis {
    let request: AdvisorRequest
    let base: BattleInput

    struct Spell {
        var source: AdvisorAction.SpellSource
        var index: Int
        var card: AdvisorCard
        var options: [TavernSpellEffect]
    }

    func price(_ card: AdvisorCard) -> Int { card.cost ?? AdvisorRequest.defaultMinionCost }

    var minions: [BattleEntity] { request.board.map(\.entity) }

    /// The combat with these minions (left to right) and hand. Anything else on the baseline's
    /// board (not a minion the request lists) keeps its position.
    func input(minions: [BattleEntity], hand: [BattleEntity]? = nil, secrets: [BattleSecret]? = nil) -> BattleInput {
        var input = base
        let listed = Set(request.board.map(\.entity.entityId))
        var board = minions
        for (index, entity) in base.playerBoard.board.enumerated() where !listed.contains(entity.entityId) {
            board.insert(entity, at: min(index, board.count))
        }
        input.playerBoard.board = board
        if let hand { input.playerBoard.player.hand = hand }
        if let secrets { input.playerBoard.player.secrets = secrets }
        return input
    }

    func handWithout(_ entityID: Int) -> [BattleEntity] {
        base.playerBoard.player.hand.filter { $0.entityId != entityID }
    }

    func buy(shop k: Int, place: Int) -> AdvisorCandidate {
        let card = request.shop[k]
        var board = minions
        board.insert(card.entity, at: min(place, board.count))
        return AdvisorCandidate(.buy(shop: k, cardID: card.cardID, place: place), input: input(minions: board))
    }

    func play(hand h: Int, place: Int) -> AdvisorCandidate {
        let card = request.hand[h]
        var board = minions
        board.insert(card.entity, at: min(place, board.count))
        return AdvisorCandidate(
            .play(hand: h, cardID: card.cardID, place: place),
            input: input(minions: board, hand: handWithout(card.entity.entityId))
        )
    }

    func sell(board i: Int) -> AdvisorCandidate {
        var board = minions
        let sold = board.remove(at: i)
        return AdvisorCandidate(.sell(board: i, cardID: sold.cardId), input: input(minions: board))
    }

    func swap(shop k: Int, sell i: Int) -> AdvisorCandidate {
        let card = request.shop[k]
        var board = minions
        let sold = board[i]
        board[i] = card.entity
        return AdvisorCandidate(
            .swap(shop: k, cardID: card.cardID, sell: i, soldCardID: sold.cardId), input: input(minions: board)
        )
    }

    func move(board i: Int, to: Int) -> AdvisorCandidate {
        var board = minions
        let minion = board.remove(at: i)
        board.insert(minion, at: to)
        return AdvisorCandidate(.move(board: i, cardID: minion.cardId, to: to), input: input(minions: board))
    }

    /// The weakest minion (least attack + health; the leftmost of equals): what a swap sells first.
    func weakest() -> Int? {
        minions.indices.min { (minions[$0].attack + minions[$0].health, $0) < (minions[$1].attack + minions[$1].health, $1) }
    }

    /// Modelled tavern spells the player can cast now: in the shop and affordable, or in hand.
    func castableSpells() -> [Spell] {
        var spells: [Spell] = []
        for (k, card) in request.shop.enumerated() where card.kind == .tavernSpell && price(card) <= request.gold {
            if let options = TavernSpellEffect.options(of: card.cardID) {
                spells.append(Spell(source: .shop, index: k, card: card, options: options))
            }
        }
        for (h, card) in request.hand.enumerated() where card.kind == .tavernSpell && !card.entity.locked {
            if let options = TavernSpellEffect.options(of: card.cardID) {
                spells.append(Spell(source: .hand, index: h, card: card, options: options))
            }
        }
        return spells
    }

    /// The minion a targeted spell most likely goes on: the strongest for a buff, the weakest for
    /// setting stats (the leftmost of equals). Nil with an empty board.
    func defaultTarget(for effect: TavernSpellEffect) -> Int? {
        let strength = { (i: Int) in minions[i].attack + minions[i].health }
        if case .setTargetStats = effect {
            return minions.indices.min { (strength($0), $0) < (strength($1), $1) }
        }
        return minions.indices.min { (-strength($0), $0) < (-strength($1), $1) }
    }

    func cast(_ spell: Spell, option: Int, target: Int?) -> AdvisorCandidate {
        var board = minions
        var secrets = base.playerBoard.player.secrets
        spell.options[option].apply(to: &board, secrets: &secrets, target: target)
        let hand = spell.source == .hand ? handWithout(spell.card.entity.entityId) : nil
        return AdvisorCandidate(
            .cast(from: spell.source, index: spell.index, cardID: spell.card.cardID, option: option, target: target,
                  targetCardID: target.map { minions[$0].cardId }),
            input: input(minions: board, hand: hand, secrets: secrets)
        )
    }
}
