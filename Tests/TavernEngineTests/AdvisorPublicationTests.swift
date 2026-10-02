import Foundation
import Testing
import TavernEngine

@Suite("Advisor publication identity", .timeLimit(.simulationWait))
struct AdvisorPublicationTests {
    typealias S = AdvisorSynthetic

    actor PauseThirdSimulation {
        private var calls = 0
        private var paused: CheckedContinuation<Void, Never>?
        var isPaused: Bool { paused != nil }

        func enter() async {
            calls += 1
            if calls == 3 {
                // Deliberately complete after cancellation to exercise stale-result rejection.
                await withCheckedContinuation { paused = $0 }
            }
        }

        func release() {
            paused?.resume()
            paused = nil
        }
    }

    @Test("Partials keep their request identity through a same-turn replacement", arguments: [1, 5, 6, 7, 8, 9])
    @MainActor func replacement(version: Int) async throws {
        let first = try RecruitPlannerTests.request(
            board: [S.boardMinion(1, "body", attack: 3, health: 4),
                    S.boardMinion(2, "other", attack: 4, health: 5)],
            shop: [S.shopMinion(901, attack: 10, health: 10), S.shopMinion(902, attack: 6, health: 8)], gold: 3)
        var second = first
        second.gold = 4
        second.shop[0].entity.attack = 20
        #expect(first.id == second.id)
        var plan = S.plan; plan.version = version
        let gate = PauseThirdSimulation(), stub = S.Stub(baseline: 0)
        let simulate: AdvisorEvaluation.Simulate = { input, budget, _ in
            await gate.enter()
            return stub.odds(input, simulations: budget.simulations)
        }
        let runner = AdvisorRunner(simulate: simulate, plan: plan, debounce: .zero,
                                   timeBudget: .seconds(3600), refreshInterval: .zero)
        defer {
            runner.cancel()
            runner.onChange = nil
            Task { await gate.release() }
        }
        var shown: [AdviceView] = []
        runner.onChange = { view in
            guard let view else { return }
            guard let request = runner.currentRequest else {
                Issue.record("A displayed result must have its matching request")
                return
            }
            #expect(view.fingerprint == AdviceView.fingerprint(of: request, version: view.plan.version))
            shown.append(view)
        }
        runner.update(first)
        try await waitUntil { runner.current?.evaluations == 2 }
        while !(await gate.isPaused) { try await Task.sleep(for: .milliseconds(1)) }
        let firstFingerprint = AdviceView.fingerprint(of: first, version: version)
        let secondFingerprint = AdviceView.fingerprint(of: second, version: version)
        #expect(firstFingerprint != secondFingerprint)
        #expect(shown.filter { $0.fingerprint == firstFingerprint && $0.evaluations > 0 }.count == 2)

        runner.update(second)
        if version < 3 {
            #expect(runner.current?.fingerprint == firstFingerprint && runner.current?.isUpdating == true)
            #expect(runner.currentRequest == first)
        } else {
            #expect(runner.current?.fingerprint == secondFingerprint && runner.current?.advice.status == .thinking)
            #expect(runner.currentRequest == second)
        }
        await gate.release()
        try await waitUntil { runner.current?.fingerprint == secondFingerprint && runner.current?.isComplete == true }
        for _ in 0..<10 { await Task.yield() }
        let replacement = try #require(shown.firstIndex { $0.fingerprint == secondFingerprint })
        #expect(shown[replacement...].allSatisfy { $0.fingerprint == secondFingerprint })
        let final = try #require(runner.current)
        #expect(!final.isUpdating && final.failure == nil && runner.currentRequest == second)
        let replayed = try await final.replaying(second, simulate: S.simulate(stub))
        #expect(replayed == final)
    }

    @Test("Validated partials still reject changed requests, forged fingerprints and changed policies")
    func diagnosticValidation() throws {
        let request = try RecruitPlannerTests.request(shop: [S.shopMinion(1, attack: 5, health: 5)])
        var trace = AdvisorDecisionTrace()
        var view = AdviceView(request: request, plan: .live,
                              advice: Advice(status: .noStrongRecommendation), evaluations: 1)
        trace.record(request: request, displayed: view)
        view.evaluations = 2
        trace.record(request: request, displayed: view)
        #expect(trace.decisions.count == 1 && trace.decisions.last?.displayed.evaluations == 2)

        let valid = trace.decisions
        var different = request; different.gold += 1
        #expect(different.id == request.id)
        trace.record(request: different, displayed: view)
        var forged = view; forged.fingerprint = "unrelated"
        trace.record(request: request, displayed: forged)
        var changedPolicy = view; changedPolicy.plan.version = 5
        trace.record(request: request, displayed: changedPolicy)
        #expect(trace.decisions == valid)

        changedPolicy = AdviceView(request: request, plan: changedPolicy.plan,
                                   advice: view.advice, evaluations: 3)
        trace.record(request: request, displayed: changedPolicy)
        #expect(trace.decisions.count == 2 && trace.decisions.last?.displayed.plan.version == 5)

        // A legacy policy intentionally ignores recruit metadata. Revalidating a changed
        // request must continue to honor that policy's original fingerprint contract.
        var legacyPlan = S.plan; legacyPlan.version = 1
        let legacy = AdviceView(request: request, plan: legacyPlan, advice: view.advice)
        trace.record(request: request, displayed: legacy)
        var reconstructed = request; reconstructed.recruit?.evaluationVersion = 6
        trace.record(request: reconstructed, displayed: legacy)
        #expect(trace.decisions.last?.request == reconstructed)
        #expect(trace.decisions.last?.displayed == legacy)
    }
}
