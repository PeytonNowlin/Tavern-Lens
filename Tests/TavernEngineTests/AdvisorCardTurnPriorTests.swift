import Foundation
import Testing
import TavernEngine

@Suite("Policy 11 card-turn purchase prior")
struct AdvisorCardTurnPriorTests {
    typealias S = AdvisorSynthetic
    static let checkedAt = Date(timeIntervalSince1970: 1_791_003_600)

    static func request(version: Int = 11) throws -> AdvisorRequest {
        var request = try RecruitPlannerTests.request(
            board: [S.boardMinion(1, "existing", attack: 2, health: 2)],
            shop: [S.shopMinion(2, attack: 2, health: 2, cardID: "buy")])
        request.preview.bgTurn = 3
        request.preview.input?.gameState.currentTurn = 3
        request.recruit!.input.gameState.currentTurn = 3
        request.recruit!.evaluationVersion = version
        request.cardTurnStatsCheckedAt = checkedAt
        let date = ISO8601DateFormatter().string(from: checkedAt)
        request.cardTurnStats = CardTurnStats(lastUpdateDate: date, dataPoints: 5000, timePeriod: "last-patch",
            cardStats: ["existing", "buy"].map { id in
                .init(cardId: id, totalPlayed: 1000, averagePlacement: 3, averagePlacementOther: 5,
                    turnStats: [.init(turn: request.preview.bgTurn, totalPlayed: 1000, totalOther: 2000,
                        averagePlacement: 3, averagePlacementOther: 5)])
            })
        return request
    }

    @Test("Only a new purchased and deployed minion receives bounded influence")
    func deployedPurchase() throws {
        let request = try Self.request(), context = request.recruit!
        let baseline = RecruitState(request: request, context: context)
        #expect(RecruitCardTurnPrior.value(baseline, request: request, context: context) == 0)
        let buy = try RecruitPlannerTests.action(.buy, baseline, context, id: 2)
        let held = try #require(RecruitPlanner.applying(buy, to: baseline, context: context))
        #expect(RecruitCardTurnPrior.value(held, request: request, context: context) == 0)
        let play = try RecruitPlannerTests.action(.play, held, context, id: 2)
        let deployed = try #require(RecruitPlanner.applying(play, to: held, context: context))
        let prior = RecruitCardTurnPrior.value(deployed, request: request, context: context)
        #expect(prior > 0 && prior <= RecruitCardTurnPrior.maximumPlanInfluence)
        var without = request; without.cardTurnStats = nil
        #expect(abs(RecruitPlanner.value(deployed, request: request, context: context).total
            - RecruitPlanner.value(deployed, request: without, context: context).total - prior) < 0.00001)
        let replay = try JSONDecoder().decode(AdvisorRequest.self, from: JSONEncoder().encode(request))
        #expect(RecruitCardTurnPrior.value(deployed, request: replay, context: context) == prior)
    }

    @Test("Older policies, wrong turns, stale or missing populations cannot change ranking")
    func boundaries() throws {
        var request = try Self.request()
        let context = request.recruit!, baseline = RecruitState(request: request, context: context)
        let held = try #require(RecruitPlanner.applying(RecruitPlannerTests.action(.buy, baseline, context),
            to: baseline, context: context))
        let state = try #require(RecruitPlanner.applying(RecruitPlannerTests.action(.play, held, context),
            to: held, context: context))
        var old = context; old.evaluationVersion = 10
        #expect(RecruitCardTurnPrior.value(state, request: request, context: old) == 0)
        let legacyFingerprint = AdviceView.fingerprint(of: request, version: 10)
        var noStats = request; noStats.cardTurnStats = nil; noStats.cardTurnStatsCheckedAt = nil
        #expect(AdviceView.fingerprint(of: noStats, version: 10) == legacyFingerprint)
        #expect(AdviceView.fingerprint(of: noStats, version: 11) != AdviceView.fingerprint(of: request, version: 11))
        request.cardTurnStats!.cardStats[1].turnStats[0].turn = request.preview.bgTurn + 1
        #expect(RecruitCardTurnPrior.value(state, request: request, context: context) == 0)
        request = try Self.request(); request.cardTurnStats!.cardStats[1].turnStats[0].totalOther = 199
        #expect(RecruitCardTurnPrior.value(state, request: request, context: context) == 0)
        request = try Self.request(); request.cardTurnStatsCheckedAt = Self.checkedAt.addingTimeInterval(49 * 3600)
        #expect(RecruitCardTurnPrior.value(state, request: request, context: context) == 0)
        request = try Self.request(); request.cardTurnStatsCheckedAt = nil
        #expect(RecruitCardTurnPrior.value(state, request: request, context: context) == 0)
        request = try Self.request(); request.cardTurnStats!.cardStats[1].turnStats[0].averagePlacement = 6
        #expect(RecruitCardTurnPrior.value(state, request: request, context: context) == 0)
    }

    @Test("Activation price provenance cannot change older policy fingerprints")
    func legacyActivationPrice() throws {
        var request = try Self.request()
        var context = request.recruit!
        context.activations = [1: .init(ready: true, cost: 1)]
        request.recruit = context
        let legacy = AdviceView.fingerprint(of: request, version: 10)
        let current = AdviceView.fingerprint(of: request, version: 11)
        context.activations = [1: .init(ready: true, cost: 1, costObserved: false)]
        request.recruit = context
        #expect(AdviceView.fingerprint(of: request, version: 10) == legacy)
        #expect(AdviceView.fingerprint(of: request, version: 11) != current)
    }

    @Test("Even well-populated late-turn associations cannot contribute to live purchase scoring")
    func lateTurn() throws {
        var request = try Self.request()
        request.preview.bgTurn = 4
        request.cardTurnStats!.cardStats[1].turnStats[0].turn = 4
        let context = request.recruit!, initial = RecruitState(request: request, context: context)
        let held = try #require(RecruitPlanner.applying(RecruitPlannerTests.action(.buy, initial, context, id: 2),
            to: initial, context: context))
        let deployed = try #require(RecruitPlanner.applying(RecruitPlannerTests.action(.play, held, context, id: 2),
            to: held, context: context))
        #expect(RecruitCardTurnPrior.value(deployed, request: request, context: context) == 0)
    }
}
