import Foundation
import Testing
import TavernEngine

@Suite("Contextual build readiness")
struct AdvisorBuildReadinessTests {
    typealias S = AdvisorSynthetic
    static let aviator = "BG34_140"
    static let leeroy = "BG23_318"
    static let bile = "BG33_318"

    static func legacyBuild() -> AdvisorBuild {
        var build = AdvisorBuild(id: "hsreplay_8", name: "Murlocs - Venom Scam", share: 1,
            core: [leeroy, bile, aviator], addons: ["support"], coreTiers: [leeroy: 5, bile: 5, aviator: 2])
        build.requirements = [BuildRequirement(role: "Venom replacement", anyOf: [leeroy, bile, aviator])]
        return build
    }

    static func request(board: [AdvisorCard]? = nil, hand: [AdvisorCard] = [], version: Int = 10) throws -> AdvisorRequest {
        var request = try RecruitPlannerTests.request(
            board: board ?? [S.boardMinion(1, aviator, attack: 8, health: 10)], hand: hand)
        request.tier = 2
        request.recruit?.evaluationVersion = version
        request.strategyCatalog = [legacyBuild()]
        for id in [aviator, aviator + "_G", leeroy, leeroy + "_G", bile, bile + "_G", "BG34_858"] {
            request.recruit?.definitions[id] = PoolFixture.cards[id]
        }
        return request
    }

    static func synergy(_ request: AdvisorRequest, build: AdvisorBuild) -> Double {
        var scored = request
        scored.builds = [build]
        let context = scored.recruit!
        return RecruitPlanner.value(RecruitState(request: scored, context: context), request: scored, context: context).synergy
    }

    @Test("Aviator alone or with a non-lethal locked payload cannot complete the Venom recipe")
    func aviatorDoesNotSupplyVenom() throws {
        let source = try #require(HSReplayCompositions.bundled())
        let recipe = try #require(source.catalog(pool: PoolFixture.pool).build("hsreplay_8"))
        #expect(recipe.core.contains(Self.aviator), "Aviator remains useful support in the guide")
        #expect(recipe.requirements?.first?.anyOf == [Self.leeroy, Self.bile])
        #expect(recipe.whenToCommit?.contains("Expert Aviator") == false)

        for payload in 0...2 {
            var hand: [AdvisorCard] = []
            if payload > 0 {
                var revenant = S.boardMinion(2, "BG34_858", attack: 3, health: 6)
                revenant.entity.locked = payload == 1
                hand = [revenant]
            }
            let current = try Self.request(hand: hand)
            let selection = try #require(AdvisorStrategy.select(current))
            #expect(!selection.guidance.committed && selection.build.share == 0.5)
            #expect(selection.guidance.missing == [Self.leeroy, Self.bile])
            #expect(selection.guidance.search?.minimumPurchaseGold == 3)

            var archived = current
            archived.recruit?.evaluationVersion = 9
            let previous = try #require(AdvisorStrategy.select(archived))
            #expect(previous.guidance.committed && previous.build.share == 1)
            // Value must normalize the original captured build too, even without selecting it first.
            #expect(Self.synergy(current, build: Self.legacyBuild()) < Self.synergy(archived, build: Self.legacyBuild()))
        }
    }

    @Test("Real lethal utility still qualifies, while locked engine roles wait until playable")
    func utilityAndLockedRoles() throws {
        for id in [Self.leeroy, Self.leeroy + "_G", Self.bile, Self.bile + "_G"] {
            let body = S.boardMinion(2, id, attack: 6, health: 3, golden: id.hasSuffix("_G"))
            let onBoard = try Self.request(board: [body])
            let ready = try #require(AdvisorStrategy.select(onBoard))
            #expect(ready.guidance.committed && ready.guidance.missing.isEmpty)

            var lockedBody = body
            lockedBody.entity.locked = true
            var locked = try Self.request(hand: [lockedBody])
            let waiting = try #require(AdvisorStrategy.select(locked))
            #expect(!waiting.guidance.committed)
            #expect(waiting.guidance.search?.minimumPurchaseGold == 0, "owned potential need not be purchased again")
            locked.hand[0].entity.locked = false
            let unlocked = try #require(AdvisorStrategy.select(locked))
            #expect(unlocked.guidance.committed)
        }

        var engine = S.boardMinion(2, "BG34_858", attack: 3, health: 6)
        engine.entity.locked = true
        var request = try Self.request(hand: [engine])
        var build = AdvisorBuild(id: "growth", name: "Growth", share: 1, core: [engine.cardID], addons: [])
        build.requirements = [BuildRequirement(role: "scaling engine", anyOf: [engine.cardID])]
        request.strategyCatalog = [build]
        let waiting = try #require(AdvisorStrategy.select(request))
        #expect(!waiting.guidance.committed)
        let lockedValue = Self.synergy(request, build: build)
        request.hand[0].entity.locked = false
        let ready = try #require(AdvisorStrategy.select(request))
        #expect(ready.guidance.committed && Self.synergy(request, build: build) > lockedValue)
        request.hand[0].entity.locked = true
        request.recruit?.evaluationVersion = 9
        #expect(AdvisorStrategy.select(request)?.guidance.committed == true, "captured older policies retain their readiness rules")
    }
}
