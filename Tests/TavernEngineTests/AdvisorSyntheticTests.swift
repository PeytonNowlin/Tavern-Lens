import Foundation
import Testing
import TavernEngine

/// The advisor on synthetic recruit states (the committed turn-11 side with a made-up shop), scored
/// by a stub whose odds follow the board's stats: which actions are generated, how they're ranked,
/// the reasons and confidence shown, and that the same state always gives the same advice.
@Suite("Advisor on synthetic states")
struct AdvisorSyntheticTests {
    typealias S = AdvisorSynthetic

    static func run(
        _ request: AdvisorRequest, _ stub: S.Stub, plan: AdvisorPlan = S.plan, calls: S.Calls = S.Calls(),
        limit: Int? = nil
    ) async throws -> AdvisorEvaluation.Progress {
        try await AdvisorEvaluation.run(request, plan: plan, limit: limit, simulate: S.simulate(stub, calls: calls))
    }

    static func stub(_ request: AdvisorRequest, base: Double = 50, leftmostWeight: Double = 1) -> S.Stub {
        var stub = S.Stub(baseline: 0, base: base, leftmostWeight: leftmostWeight)
        stub.baseline = Int(stub.strength(request.preview.input!))
        return stub
    }

    /// The suggestions' actions, in rank order.
    static func actions(_ advice: Advice) -> [AdvisorAction] { advice.suggestions.map(\.action) }

    static func isBuy(_ action: AdvisorAction, shop index: Int? = nil) -> Bool {
        if case .buy(let shop, _, _) = action { return index.map { $0 == shop } ?? true }
        return false
    }

    static func isSwap(_ action: AdvisorAction) -> Bool {
        if case .swap = action { true } else { false }
    }

    static func isCast(_ action: AdvisorAction, from source: AdvisorAction.SpellSource, index: Int) -> Bool {
        if case .cast(let from, let i, _, _, _, _) = action { return from == source && i == index }
        return false
    }

    static func stats(_ card: AdvisorCard) -> Int { card.entity.attack + card.entity.health }

    @Test("Candidates: affordable buys, playable hand minions, sells, modelled spells and the tavern buttons")
    func candidates() async throws {
        // A strong minion in hand is played.
        let hand = try S.request(boardCount: 5, hand: [S.shopMinion(905, attack: 30, health: 30)], gold: 0)
        let played = try await Self.run(hand, Self.stub(hand)).advice
        guard case .play(hand: 0, _, _) = try #require(played.suggestions.first).action else {
            Issue.record("top is \(Self.actions(played))")
            return
        }

        // The affordable buy is suggested; the dearer minion isn't, however strong, nor is a 7-gold level at 4 gold.
        let shop = [S.shopMinion(901, attack: 5, health: 5), S.shopMinion(902, attack: 40, health: 40, cost: 5)]
        let buying = try S.request(boardCount: 5, shop: shop, gold: 4, levelCost: 7)
        let bought = try await Self.run(buying, Self.stub(buying)).advice
        #expect(Self.actions(bought).contains { Self.isBuy($0, shop: 0) }, "\(Self.actions(bought))")
        #expect(!Self.actions(bought).contains { Self.isBuy($0, shop: 1) || Self.isSwap($0) })
        #expect(!Self.actions(bought).contains { if case .level = $0 { true } else { false } })

        // A minion that costs the combat more than its stats are worth is sold.
        let selling = try S.request(boardCount: 5, gold: 0)
        let weak = try #require(selling.board.indices.min { Self.stats(selling.board[$0]) < Self.stats(selling.board[$1]) })
        var stub = Self.stub(selling)
        let entity = selling.board[weak].entity
        stub.minionPoints[entity.entityId] = -Double(entity.attack + entity.health) / stub.perPoint - 20
        let sold = try await Self.run(selling, stub).advice
        #expect(sold.suggestions.first?.action == .sell(board: weak, cardID: entity.cardId), "\(Self.actions(sold))")

        // Banana is modelled, so it's cast; Enchanted Lasso isn't, so it never is.
        let spells = try S.request(boardCount: 5, shop: [S.spell(903, "BG28_897"), S.spell(904, "BG28_512")], gold: 3)
        let cast = try await Self.run(spells, Self.stub(spells)).advice
        #expect(Self.actions(cast).contains { Self.isCast($0, from: .shop, index: 0) }, "\(Self.actions(cast))")
        #expect(!Self.actions(cast).contains { Self.isCast($0, from: .shop, index: 1) })

        // Shiny Ring from hand buffs the board, so it's played.
        let ring = try S.request(boardCount: 5, hand: [S.spell(906, "BG28_168")], gold: 0)
        let ringed = try await Self.run(ring, Self.stub(ring)).advice
        #expect(Self.actions(ringed).contains { Self.isCast($0, from: .hand, index: 0) }, "\(Self.actions(ringed))")
    }

    @Test("Moves: with the leftmost minion counting most, a stronger minion is moved to the front")
    func moves() async throws {
        let request = try S.request(boardCount: 5, gold: 0)
        let advice = try await Self.run(request, Self.stub(request, leftmostWeight: 3)).advice
        let top = try #require(advice.suggestions.first)
        guard case .move = top.action else {
            Issue.record("top is \(Self.actions(advice))")
            return
        }
        #expect(top.gain > 0 && top.targets.first?.kind == .board)
    }

    @Test("A full board swaps instead of buying; a full hand can't buy; no data means no suggestions")
    func limits() async throws {
        let shop = [S.shopMinion(901, attack: 30, health: 30)]
        // 2 gold + 1 for the sale buys it, in place of a minion.
        let full = try S.request(boardCount: 7, shop: shop, gold: 2)
        let swapped = try await Self.run(full, Self.stub(full)).advice
        #expect(!Self.actions(swapped).contains { Self.isBuy($0) })
        #expect(Self.actions(swapped).contains(where: Self.isSwap), "\(Self.actions(swapped))")

        let hand = (0..<10).map { S.shopMinion(950 + $0, attack: 1, health: 1) }
        let crowded = try S.request(boardCount: 7, shop: shop, hand: hand)
        let stuck = try await Self.run(crowded, Self.stub(crowded)).advice
        #expect(!Self.actions(stuck).contains { Self.isBuy($0) || Self.isSwap($0) }, "\(Self.actions(stuck))")

        let unseen = try S.request(boardCount: 5, shop: shop, hasData: false)
        let none = try await Self.run(unseen, Self.stub(try S.request())).advice
        #expect(none.status == .noData && none.suggestions.isEmpty)
    }

    @Test("Without data the advice says so and simulates nothing")
    func noData() async throws {
        let request = try S.request(boardCount: 5, shop: [S.shopMinion(901, attack: 5, health: 5)], hasData: false)
        let calls = S.Calls()
        let result = try await Self.run(request, Self.stub(try S.request()), calls: calls)
        #expect(result.advice.status == .noData && result.advice.note == "No data: no opponent fought yet")
        #expect(result.advice.suggestions.isEmpty && calls.all.isEmpty)
    }

    @Test("A clear improvement comes first, with its reason, high confidence and its shop card to highlight")
    func clearImprovement() async throws {
        let shop = [S.shopMinion(901, attack: 2, health: 2), S.shopMinion(902, attack: 20, health: 20)]
        let request = try S.request(boardCount: 5, shop: shop, gold: 3)
        let advice = try await Self.run(request, Self.stub(request)).advice
        #expect(advice.status == .recommendation)
        let top = try #require(advice.suggestions.first)
        guard case .buy(let shopIndex, _, _) = top.action else { Issue.record("top is \(top.action)"); return }
        #expect(shopIndex == 1)
        #expect(top.reason == "+20% win vs next opponent")
        #expect(top.confidence == .high)
        #expect(top.targets == [AdvisorTarget(.shop, 1)])
        #expect(top.terms.combat == top.gain && top.terms.lobby == nil && top.terms.build == nil,
                "no lobby or builds in the request: the combat term only (the level is out of reach, so no tempo cost)")
        // Each suggestion has a reason and a confidence, and none makes the combat clearly worse.
        for suggestion in advice.suggestions {
            #expect(!suggestion.reason.isEmpty)
            #expect(suggestion.gain >= 0, "\(suggestion.action) gains \(suggestion.gain)")
        }
        #expect(advice.suggestions.map(\.rank) == Array(1...advice.suggestions.count))
    }

    @Test("A buy is suggested once, at its best placement")
    func placement() async throws {
        let shop = [S.shopMinion(902, attack: 30, health: 30)]
        let request = try S.request(boardCount: 1, shop: shop, gold: 3)
        // The leftmost minion's stats count three times: the 30/30 belongs in front of the 21/21.
        var stub = Self.stub(request, leftmostWeight: 3)
        stub.perPoint = 10
        let advice = try await Self.run(request, stub).advice
        let buys = advice.suggestions.filter { if case .buy = $0.action { true } else { false } }
        #expect(buys.count == 1)
        #expect(buys.first?.action == .buy(shop: 0, cardID: "BG36_106", place: 0))
    }

    @Test("Close options give no strong recommendation, and say why")
    func close() async throws {
        let shop = [S.shopMinion(901, attack: 10, health: 10), S.shopMinion(902, attack: 10, health: 10)]
        let request = try S.request(boardCount: 5, shop: shop, gold: 3)
        let advice = try await Self.run(request, Self.stub(request)).advice
        #expect(advice.status == .noStrongRecommendation)
        #expect(advice.note == "Options are close")
        #expect(advice.suggestions.count >= 2, "the close options are still listed")
    }

    @Test("When nothing on the board helps: level when it's due, refresh when behind, neither when ahead of the curve")
    func nothingHelps() async throws {
        let shop = [S.shopMinion(901, attack: 0, health: 1)]
        // Tier 4 on turn 11: two tiers behind the levelling curve.
        let behindCurve = try S.request(boardCount: 7, shop: shop, gold: 8, tier: 4, levelCost: 7)
        let winning = try await Self.run(behindCurve, Self.stub(behindCurve, base: 70)).advice
        #expect(winning.suggestions.map(\.action) == [.level(cost: 7, toTier: 5)], "a refresh isn't worth its gold at 70%")
        #expect(winning.suggestions.first?.reason == "Behind the levelling curve (tier 4)")
        #expect(winning.suggestions.first?.confidence == .medium, "a rule of thumb, once everything is scored")
        #expect(winning.suggestions.first?.targets == [AdvisorTarget(.levelButton)])
        #expect(winning.suggestions.first?.terms.economy == 6.5, "levelling now 15.5 vs next turn 9")

        let losing = try await Self.run(behindCurve, Self.stub(behindCurve, base: 20)).advice
        #expect(losing.suggestions.map(\.action) == [.level(cost: 7, toTier: 5), .roll(cost: 1)])
        #expect(losing.suggestions[1].reason == "No shop card helps (20% win)")
        #expect(losing.suggestions[1].terms.economy == 3.8, "a fresh shop 6 × 80% less its gold")

        // Tier 5 on turn 7 is ahead of the curve: levelling at 9 now isn't worth it, refreshing is.
        let aheadOfCurve = try S.request(boardCount: 7, shop: shop, gold: 10, tier: 5, levelCost: 9, bgTurn: 7, income: 9)
        let behindOnBoard = try await Self.run(aheadOfCurve, Self.stub(aheadOfCurve, base: 10)).advice
        #expect(behindOnBoard.suggestions.map(\.action) == [.roll(cost: 1)])
    }

    @Test("Freeze is suggested when a shop card worth buying is too dear for now")
    func freeze() async throws {
        let shop = [S.shopMinion(901, attack: 15, health: 15, cost: 5)]
        let request = try S.request(boardCount: 5, shop: shop, gold: 3, levelCost: 9)
        let advice = try await Self.run(request, Self.stub(request)).advice
        let freeze = try #require(advice.suggestions.first { $0.action == .freeze })
        #expect(freeze.reason == "Saves a +15% win buy for next turn")
        #expect(freeze.targets == [AdvisorTarget(.freezeButton)])
        #expect(!advice.suggestions.contains { if case .buy = $0.action { true } else { false } })
    }

    @Test("An old opponent board caps confidence at medium, and the advice says which turn it's from")
    func stale() async throws {
        let shop = [S.shopMinion(902, attack: 20, health: 20)]
        let request = try S.request(boardCount: 5, shop: shop, gold: 3, seenTurn: 7)
        let advice = try await Self.run(request, Self.stub(request)).advice
        #expect(advice.status == .recommendation)
        #expect(advice.suggestions.first?.confidence == .medium)
        #expect(advice.note == "Their board is from turn 7")
    }

    @Test("Cutting the risk of dying is the reason given when it's the big change")
    func lethal() async throws {
        let shop = [S.shopMinion(902, attack: 20, health: 20)]
        let request = try S.request(boardCount: 5, shop: shop, gold: 3)
        var stub = Self.stub(request, base: 30)
        stub.lethal = 30
        stub.lethalAbove = stub.baseline + 1
        let top = try #require(try await Self.run(request, stub).advice.suggestions.first)
        #expect(top.reason == "Cuts lethal risk 30% → 0%")
    }

    @Test("The same state gives the same advice; the best options and the baseline get the refine pass's extra simulations")
    func deterministic() async throws {
        let shop = [S.shopMinion(901, attack: 5, health: 5), S.shopMinion(902, attack: 9, health: 3), S.spell(903, "BG28_897")]
        let request = try S.request(boardCount: 6, shop: shop, gold: 7)
        let stub = Self.stub(request, leftmostWeight: 2)
        let first = try await Self.run(request, stub)
        let second = try await Self.run(request, stub)
        #expect(first.advice == second.advice && first.evaluations == second.evaluations && first.isComplete)
        let refined = S.plan.simulations + S.plan.refineSimulations
        #expect(first.advice.baseline?.simulations == refined, "the baseline is refined")
        let top = try #require(first.advice.suggestions.first)
        #expect(top.odds?.simulations == refined, "the best option is refined")
        let boardChanges = first.advice.suggestions.filter { $0.action.changesBoard }
        #expect(boardChanges.filter { $0.odds?.simulations == refined }.count <= S.plan.refinedGroups)
    }

    @Test("Stopping after N evaluations gives the advice shown after N, so a bookmark's advice replays")
    func replayPrefix() async throws {
        let shop = [S.shopMinion(901, attack: 5, health: 5), S.shopMinion(902, attack: 9, health: 3)]
        let request = try S.request(boardCount: 6, shop: shop, gold: 7)
        let stub = Self.stub(request)
        var reports: [AdvisorEvaluation.Progress] = []
        _ = try await AdvisorEvaluation.run(request, plan: S.plan, simulate: S.simulate(stub)) { reports.append($0) }
        for n in [1, 3, 8] {
            let shown = try #require(reports.first { $0.evaluations == n })
            let view = AdviceView(request: request, plan: S.plan, advice: shown.advice, evaluations: n)
            let replayed = try await view.replaying(request, simulate: S.simulate(stub))
            #expect(replayed.advice == shown.advice, "after \(n) evaluations")
            #expect(replayed.fingerprint == view.fingerprint && !replayed.isComplete)
        }
    }

    @Test("Saved advice from before a weight existed still loads, with today's default for it")
    func weightsDecodeLeniently() throws {
        let weights = try JSONDecoder().decode(AdvisorWeights.self, from: Data(#"{"combat": 2, "highZ": 4}"#.utf8))
        var expected = AdvisorWeights()
        expected.combat = 2
        expected.highZ = 4
        #expect(weights == expected)
        #expect(try JSONDecoder().decode(AdvisorWeights.self, from: JSONEncoder().encode(expected)) == expected)
    }

    @Test("Modelled tavern spells change the board as their text says")
    func spells() async throws {
        // Winner's Bread (+2/+3) on the 67/67, Perfect Vision (20/20) on the weakest, Energizing Chamber (+7/+7 Deity).
        let shop = [S.spell(903, "BG36_883"), S.spell(904, "BG28_838"), S.spell(905, "BG36_371")]
        let request = try S.request(boardCount: 5, shop: shop, gold: 10)
        let calls = S.Calls()
        _ = try await Self.run(request, Self.stub(request), calls: calls)
        // What the simulator was asked to fight with.
        let boards = calls.all.map(\.input.playerBoard).filter { $0.board.count == 5 }
        #expect(boards.contains { $0.board[3].attack == 69 && $0.board[3].health == 70 }, "Winner's Bread on the 67/67")
        #expect(boards.contains { $0.board[4].attack == 20 && $0.board[4].maxHealth == 20 },
                "Perfect Vision on the 14/12 golden, the weakest")
        #expect(boards.contains { $0.player.secrets.first?.tags == ["4914": 243, "4915": 229] }, "Energizing Chamber on the Deity")
    }
}

/// The advisor runner with the stub scorer: it follows the state within the turn, drops stale
/// scoring, and keeps to its time budget.
@Suite("Advisor runner", .timeLimit(.simulationWait))
@MainActor
struct AdvisorRunnerTests {
    typealias S = AdvisorSynthetic

    static func wait(_ runner: AdvisorRunner, until done: (AdviceView?) -> Bool) async throws {
        try await waitUntil { done(runner.current) }
    }

    @Test("Suggestions follow the state within the turn: a new shop is re-scored, the old scoring dropped")
    func followsState() async throws {
        let first = try S.request(boardCount: 5, shop: [S.shopMinion(901, attack: 20, health: 20)], gold: 3)
        let second = try S.request(boardCount: 5, shop: [S.shopMinion(902, attack: 2, health: 2), S.shopMinion(903, attack: 30, health: 30)], gold: 3)
        var stub = AdvisorSyntheticTests.stub(first)
        stub.delay = .milliseconds(5)
        let calls = S.Calls()
        // No time budget to speak of: the test is about following the state, however busy the machine.
        let runner = AdvisorRunner(simulate: S.simulate(stub, calls: calls), plan: S.plan, debounce: .milliseconds(20),
                                   timeBudget: .seconds(3600), refreshInterval: .milliseconds(1))
        var views: [AdviceView?] = []
        runner.onChange = { views.append($0) }

        runner.update(first)
        #expect(runner.current?.advice.status == .thinking)
        try await Self.wait(runner) { $0?.isComplete == true }
        #expect(runner.current?.advice.suggestions.first?.action == .buy(shop: 0, cardID: "BG36_106", place: 5))

        runner.update(second)
        #expect(runner.current?.isUpdating == true, "the old advice stays up, marked updating")
        #expect(runner.current?.fingerprint == AdviceView.fingerprint(of: first))
        let switched = calls.all.count
        try await Self.wait(runner) { $0?.isComplete == true && $0?.fingerprint == AdviceView.fingerprint(of: second) }
        #expect(runner.current?.advice.suggestions.first?.action == .buy(shop: 1, cardID: "BG36_106", place: 5))
        #expect(runner.current?.isUpdating == false)
        // After the switch only the new shop was scored.
        let firstShop = Set(first.shop.map(\.entity.entityId))
        #expect(calls.all.dropFirst(switched).allSatisfy { call in
            !call.input.playerBoard.board.contains { firstShop.contains($0.entityId) }
        })
        #expect(views.contains { $0?.isUpdating == true })

        runner.update(nil)
        #expect(runner.current == nil)
    }

    @Test("The time budget stops scoring between evaluations; what was shown replays exactly")
    func timeBudget() async throws {
        let shop = [S.shopMinion(901, attack: 5, health: 5), S.shopMinion(902, attack: 9, health: 3), S.shopMinion(903, attack: 1, health: 7)]
        let request = try S.request(boardCount: 5, shop: shop, gold: 9)
        var stub = AdvisorSyntheticTests.stub(request)
        stub.delay = .milliseconds(40)
        let runner = AdvisorRunner(simulate: S.simulate(stub), plan: S.plan, debounce: .milliseconds(1),
                                   timeBudget: .milliseconds(300), refreshInterval: .milliseconds(1))
        runner.update(request)
        try await Self.wait(runner) { $0?.evaluations ?? 0 > 0 }
        try await Task.sleep(for: .milliseconds(600))
        let view = try #require(runner.current)
        #expect(!view.isComplete, "cut short by the budget")
        #expect(view.evaluations > 0 && view.evaluations < 20)
        stub.delay = nil
        let replayed = try await view.replaying(request, simulate: S.simulate(stub))
        #expect(replayed.advice == view.advice && replayed.evaluations == view.evaluations)
    }

    @Test("An unseen opponent shows no data at once, and runs nothing")
    func noData() async throws {
        let calls = S.Calls()
        let runner = AdvisorRunner(simulate: S.simulate(S.Stub(baseline: 0), calls: calls), plan: S.plan)
        runner.update(try S.request(boardCount: 5, hasData: false))
        #expect(runner.current?.advice.status == .noData)
        try await Task.sleep(for: .milliseconds(100))
        #expect(calls.all.isEmpty)
    }
}
