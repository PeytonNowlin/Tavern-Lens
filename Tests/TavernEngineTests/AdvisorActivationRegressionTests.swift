import Foundation
import Testing
import TavernEngine

@Suite("Logged minion Activate regressions")
struct AdvisorActivationRegressionTests {
    typealias S = AdvisorSynthetic

    // Game 299351837, turn 3: the captured readiness was true and the hand empty.
    // Activating Prisonguard then changed the other body from 2/1 to 5/4.
    static func prisonguardRequest(ready: Bool = true, gold: Int = 2, golden: Bool = false) throws -> AdvisorRequest {
        let id = golden ? "BG36_345_G" : "BG36_345"
        let amount = golden ? 6 : 3
        var guardCard = S.boardMinion(2, id, attack: 3, health: 3)
        guardCard.golden = golden
        var request = try RecruitPlannerTests.request(
            board: [S.boardMinion(1, "BGS_034", attack: 2, health: 1), guardCard],
            gold: gold, texts: [id: "<b>Activate (1):</b> Give another minion +\(amount)/+\(amount)."])
        request.recruit!.evaluationVersion = 7
        request.recruit!.activations = [2: .init(ready: ready, cost: 1)]
        return request
    }

    @Test("Ready Prisonguard offers and applies its targeted buff with an empty hand", arguments: [false, true])
    func prisonguardBuff(golden: Bool) throws {
        let request = try Self.prisonguardRequest(golden: golden)
        let context = request.recruit!, state = RecruitState(request: request, context: context)
        let activations = RecruitPlanner.actions(state, context: context).filter { $0.kind == .activate }
        #expect(activations.count == 1)
        let action = try #require(activations.first)
        #expect(action.entityID == 2 && action.targetID == 1)
        let after = try #require(RecruitPlanner.applying(action, to: state, context: context))
        #expect(after.gold == 1 && after.hand.isEmpty)
        #expect(after.board.map { $0.entity.attack } == [golden ? 8 : 5, 3])
        #expect(after.board.map { $0.entity.health } == [golden ? 7 : 4, 3])
        #expect(action.action.targets == [.init(.board, 1), .init(.board, 0)])
        #expect(action.title.contains(" on BGS_034"))
        #expect(try JSONDecoder().decode(AdvisorAction.self, from: JSONEncoder().encode(action.action)) == action.action)
        #expect(after.usedActivations == [2])
        #expect(RecruitPlanner.actions(after, context: context).allSatisfy { $0.kind != .activate })
        #expect(RecruitPlanner.value(after, request: request, context: context).total
                > RecruitPlanner.value(state, request: request, context: context).total)
    }

    @Test("Archived v6 retains its original Activate coverage")
    func archivedCoverage() throws {
        var request = try Self.prisonguardRequest()
        request.recruit!.evaluationVersion = 6
        let context = request.recruit!, state = RecruitState(request: request, context: context)
        #expect(RecruitPlanner.actions(state, context: context).allSatisfy { $0.kind != .activate })
    }

    @Test("Prisonguard still needs observed readiness, gold and another target")
    func prisonguardLegality() throws {
        for mode in 0..<4 {
            var request = try Self.prisonguardRequest(ready: mode != 0, gold: mode == 1 ? 0 : 2)
            if mode == 2 { request.recruit!.activations = nil }
            if mode == 3 { request.board.removeFirst() }
            let context = request.recruit!, state = RecruitState(request: request, context: context)
            #expect(RecruitPlanner.actions(state, context: context).allSatisfy { $0.kind != .activate })
        }
    }

    @Test("Buying and playing a ready Prisonguard leaves its paid activation available")
    func buyPlayActivate() throws {
        var request = try Self.prisonguardRequest(gold: 4)
        request.shop = [request.board.removeLast()]
        let context = request.recruit!
        var state = RecruitState(request: request, context: context)
        for kind in [RecruitStep.Kind.buy, .play, .activate] {
            let step = try RecruitPlannerTests.action(kind, state, context, id: 2)
            state = try #require(RecruitPlanner.applying(step, to: state, context: context))
        }
        #expect(state.gold == 0 && state.board[0].entity.attack == 5 && state.board[0].entity.health == 4)
    }

    static func decoyRequest() throws -> AdvisorRequest {
        var spell = S.spell(5, "spell")
        spell.entity.attack = 99 // Tavern spells must never participate in the highest-minion selection.
        var request = try RecruitPlannerTests.request(
            board: [S.boardMinion(1, "BG36_354", attack: 3, health: 4)],
            shop: [S.shopMinion(3, attack: 2, health: 3, cardID: "small"),
                   S.shopMinion(4, attack: 4, health: 5, cardID: "large"), spell], gold: 2,
            texts: ["BG36_354": "<b>Activate (2):</b> Steal the highest-Attack minion in the Tavern.",
                    "large": "Battlecry: Get a Tavern Coin."])
        request.recruit!.evaluationVersion = 7
        request.recruit!.activations = [1: .init(ready: true, cost: 2)]
        return request
    }

    @Test("Decoy acquires the unique highest-Attack minion without playing its battlecry")
    func decoySteal() throws {
        let request = try Self.decoyRequest(), context = request.recruit!
        let state = RecruitState(request: request, context: context)
        let action = try RecruitPlannerTests.action(.activate, state, context)
        let after = try #require(RecruitPlanner.applying(action, to: state, context: context))
        #expect(action.targetID == 4 && action.action.targets == [.init(.board, 0), .init(.shop, 1)])
        #expect(action.title.contains("steal large"))
        #expect(after.hand.map(\.cardID) == ["large"] && after.shop.map(\.cardID) == ["small", "spell"])
        #expect(after.gold == 0 && after.usedActivations == [1] && after.board == state.board)
        #expect(after.hand.first?.entity.attack == 4 && after.hand.first?.entity.health == 5)
    }

    @Test("Decoy excludes ambiguous ties and a full hand, and reports the tie boundary")
    func decoyBoundaries() throws {
        var request = try Self.decoyRequest()
        request.shop[0].entity.attack = 4
        var context = request.recruit!, state = RecruitState(request: request, context: context)
        #expect(RecruitPlanner.actions(state, context: context).allSatisfy { $0.kind != .activate })
        #expect(RecruitPlanner.search(request, context: context).limitations.contains { $0.contains("highest-Attack tie") })
        request = try Self.decoyRequest()
        request.hand = (10..<20).map { S.shopMinion($0, attack: 1, health: 1, cardID: "held\($0)") }
        context = request.recruit!; state = RecruitState(request: request, context: context)
        #expect(RecruitPlanner.actions(state, context: context).allSatisfy { $0.kind != .activate })
        context.evaluationVersion = 6
        request.hand = []
        state = RecruitState(request: request, context: context)
        #expect(RecruitPlanner.actions(state, context: context).allSatisfy { $0.kind != .activate })
    }

    @Test("Paid buff activation reaches advice with an accurate explanation and highlights")
    func recommendedBuff() async throws {
        var request = try Self.prisonguardRequest()
        request.preview.input = nil; request.preview.opponentSeenTurn = nil
        let result = try await AdvisorEvaluation.run(request, plan: .live, simulate: S.simulate(.init(baseline: 0)))
        let suggestion = try #require(result.advice.suggestions.first)
        #expect(suggestion.action == .activateMinion(board: 1, cardID: "BG36_345", cost: 1,
            target: .init(.board, 0), targetCardID: "BGS_034"))
        #expect(suggestion.targets == [.init(.board, 1), .init(.board, 0)])
        #expect(suggestion.reason.contains("Uses Activate to strengthen"))
        #expect(!suggestion.reason.lowercased().contains("discard"))
    }

    @Test("Unresolved Activate families are named explicitly without changing archived policy notes")
    func unsupportedCoverage() async throws {
        let id = "BG36_180"
        var request = try RecruitPlannerTests.request(
            board: [S.boardMinion(1, id, attack: 4, health: 5)], gold: 1,
            texts: [id: "Activate (1): Gain the stats of the next minion you buy this turn."])
        request.recruit!.activations = [1: .init(ready: true, cost: 1)]
        request.preview.input = nil; request.preview.opponentSeenTurn = nil
        for version in [6, 7] {
            var plan = AdvisorPlan.live; plan.version = version
            let result = try await AdvisorEvaluation.run(request, plan: plan, simulate: S.simulate(.init(baseline: 0)))
            #expect((result.advice.note?.contains("Activate coverage missing: \(id)") == true) == (version == 7))
        }
        let legacy = AdvisorAction.activate(board: 0, cardID: "envoy", cost: 0, discard: 1, discardedCardID: "sludge")
        #expect(try JSONDecoder().decode(AdvisorAction.self, from: JSONEncoder().encode(legacy)) == legacy)
        #expect(legacy.targets == [.init(.board, 0), .init(.hand, 1)])
    }

    @Test("Decoy acquisition completes a known triple through the shared transition")
    func decoyTriple() throws {
        var request = try Self.decoyRequest()
        request.board += [S.boardMinion(6, "large", attack: 4, health: 5),
                          S.boardMinion(7, "large", attack: 4, health: 5)]
        request.recruit!.definitions["large"]!.dbfId = 100
        request.recruit!.definitions["large"]!.battlegroundsPremiumDbfId = 101
        var golden = Card(id: "large_G", dbfId: 101, name: "Golden large")
        golden.type = "MINION"; golden.attack = 8; golden.health = 10
        golden.battlegroundsNormalDbfId = 100
        request.recruit!.definitions[golden.id] = golden
        let context = request.recruit!, state = RecruitState(request: request, context: request.recruit!)
        let after = try #require(RecruitPlanner.applying(RecruitPlannerTests.action(.activate, state, context),
            to: state, context: context))
        #expect(after.board.map(\.cardID) == ["BG36_354"])
        #expect(after.hand.map(\.cardID) == ["large_G"] && after.pendingDiscover == 1)
        #expect(after.hand[0].entity.attack == 8 && after.hand[0].entity.health == 10)
    }

    @Test("Changed Activate text and unsupported double triggers remain excluded")
    func exactCoverage() throws {
        for doubled in [false, true] {
            var request = try Self.prisonguardRequest()
            if doubled {
                let gift = "BG36_MidGameEffect_test"
                request.board[1].entity.enchantments = [try AdvisorDiscardRegressionTests.gift(gift)]
                AdvisorDiscardRegressionTests.definition(gift, "This minion's Activate triggers twice.", request: &request)
            } else {
                request.recruit!.definitions["BG36_345"]!.text = "Activate (1): Give another minion +4/+4."
            }
            let context = request.recruit!, state = RecruitState(request: request, context: context)
            #expect(RecruitPlanner.actions(state, context: context).allSatisfy { $0.kind != .activate })
        }
    }
}
