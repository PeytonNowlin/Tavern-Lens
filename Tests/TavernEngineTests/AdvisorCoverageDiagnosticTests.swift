import Foundation
import Testing
import TavernEngine

@Suite("Advisor coverage evidence")
struct AdvisorCoverageDiagnosticTests {
    @Test("Missing definitions and unsupported effects remain separate and deterministic")
    func gaps() throws {
        var request = try RecruitPlannerTests.request(
            shop: [AdvisorSynthetic.shopMinion(1, attack: 2, health: 2, cardID: "random")],
            texts: ["random": "Battlecry: Get a random minion."])
        let effects = AdvisorCoverageDiagnostic(request: request, policyVersion: 11)
        #expect(effects.missingDefinitions.isEmpty)
        #expect(effects.gaps.contains { $0.kind == .effect && $0.cardIDs == ["random"] })
        request.recruit!.definitions.removeValue(forKey: "random")
        let metadata = AdvisorCoverageDiagnostic(request: request, policyVersion: 11)
        #expect(metadata.missingDefinitions == ["random"])
        #expect(metadata.gaps.contains { $0.kind == .metadata })
        #expect(try JSONDecoder().decode(AdvisorCoverageDiagnostic.self, from: JSONEncoder().encode(metadata)) == metadata)
    }

    @Test("Missing live activation prices are recorded separately from effect coverage")
    func missingActivationPrice() throws {
        var request = try RecruitPlannerTests.request(
            board: [AdvisorSynthetic.boardMinion(1, "BG36_180", attack: 2, health: 2)],
            texts: ["BG36_180": "Activate (1): Gain the stats of the next minion you buy this turn."])
        var context = request.recruit!
        context.activations = [1: .init(ready: true, cost: 1, costObserved: false)]
        context.pendingPrisonBuys = [1: false]
        request.recruit = context
        let coverage = AdvisorCoverageDiagnostic(request: request, policyVersion: 11)
        #expect(coverage.gaps.contains {
            $0.kind == .state && $0.cardIDs == ["BG36_180"] && $0.reason.hasPrefix("Activate cost is unobserved:")
        })
        #expect(!AdvisorCoverageDiagnostic(request: request, policyVersion: 10).gaps.contains {
            $0.reason.hasPrefix("Activate cost is unobserved:")
        })
    }
}
