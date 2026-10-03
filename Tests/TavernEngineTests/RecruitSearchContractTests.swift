import Foundation
import Testing
import TavernEngine

@Suite("Recruit search boundaries and retained plans")
struct RecruitSearchContractTests {
    static func request() throws -> AdvisorRequest {
        try RecruitPlannerTests.request(
            board: [AdvisorSynthetic.boardMinion(1, "buffer", attack: 2, health: 2)],
            hand: [AdvisorSynthetic.shopMinion(2, attack: 8, health: 8, cardID: "upgrade")], gold: 0,
            texts: ["buffer": "At the end of your turn, give your other minions +2/+3."])
    }

    static func expectBaseline(_ search: RecruitSearch) {
        #expect(search.baseline.state.board.map(\.entity.entityId) == [1])
        #expect(search.baseline.state.hand.map(\.entity.entityId) == [2])
        #expect(search.baseline.state.steps == [])
        #expect(search.baseline.projection.board.map(\.entity.attack) == [2])
        #expect(search.baseline.projection.board.map(\.entity.health) == [2])
    }

    static func expectPlayedUpgrade(_ search: RecruitSearch) throws {
        #expect(search.expanded == 1)
        #expect(search.plans.map(\.id) == ["play:2:0:-1"])
        let plan = try #require(search.plans.first)
        #expect(plan.state.steps.map(\.kind) == [.play])
        #expect(plan.state.board.map(\.entity.entityId) == [1, 2])
        #expect(plan.state.board.map(\.entity.attack) == [2, 8])
        #expect(plan.state.board.map(\.entity.health) == [2, 8])
        #expect(plan.state.hand == [])
        #expect(plan.state.gold == 0)
        #expect(plan.projection.board.map(\.entity.attack) == [2, 10])
        #expect(plan.projection.board.map(\.entity.health) == [2, 11])
        #expect(plan.projection.limitations == [])
    }

    @Test("Zero depth preserves the baseline; one depth retains the complete projected play")
    func depthBoundary() throws {
        let request = try Self.request(), context = request.recruit!
        let zero = RecruitPlanner.search(request, context: context, budget: .init(depth: 0))
        Self.expectBaseline(zero)
        #expect(zero.expanded == 0)
        #expect(zero.plans.map(\.id) == [])
        let one = RecruitPlanner.search(request, context: context, budget: .init(depth: 1))
        Self.expectBaseline(one)
        try Self.expectPlayedUpgrade(one)
    }

    @Test("Exhausting the expansion budget retains the completed projection")
    func expansionBoundary() throws {
        let request = try Self.request(), context = request.recruit!
        let zero = RecruitPlanner.search(request, context: context, budget: .init(expansions: 0))
        Self.expectBaseline(zero)
        #expect(zero.expanded == 0)
        #expect(zero.plans.map(\.id) == [])
        let one = RecruitPlanner.search(request, context: context, budget: .init(expansions: 1))
        Self.expectBaseline(one)
        try Self.expectPlayedUpgrade(one)
    }

    @Test("Initial cancellation returns the baseline; partial cancellation retains its completed play")
    func cancellationBoundary() throws {
        let request = try Self.request(), context = request.recruit!
        let stopped = RecruitPlanner.search(request, context: context, shouldContinue: { false })
        Self.expectBaseline(stopped)
        #expect(stopped.expanded == 0)
        #expect(stopped.plans.map(\.id) == [])
        var firstActionAllowed = true
        let partial = RecruitPlanner.search(request, context: context, shouldContinue: {
            defer { firstActionAllowed = false }
            return firstActionAllowed
        })
        Self.expectBaseline(partial)
        try Self.expectPlayedUpgrade(partial)
    }

    @Test("A completed terminal roll remains a plan without inventing a shop or further actions")
    func terminalRoll() throws {
        var request = try RecruitPlannerTests.request(
            shop: [AdvisorSynthetic.shopMinion(3, attack: 4, health: 4, cardID: "unaffordable")], gold: 2)
        request.rollCost = 1
        let search = RecruitPlanner.search(request, context: request.recruit!, budget: .init(depth: 3))
        #expect(search.baseline.state.shop.map(\.entity.entityId) == [3])
        #expect(search.expanded == 1)
        #expect(search.plans.map(\.id) == ["roll:0:0:-1"])
        let plan = try #require(search.plans.first)
        #expect(plan.state.steps.map(\.kind) == [.roll])
        #expect(plan.projection.steps.map(\.kind) == [.roll])
        #expect(plan.state.terminal && plan.projection.terminal)
        #expect(plan.state.gold == 1 && plan.projection.gold == 1)
        #expect(plan.state.shop == [] && plan.projection.shop == [])
        #expect(plan.state.board == [] && plan.projection.board == [])
        #expect(plan.state.hand == [] && plan.projection.hand == [])
    }

    @Test("Equal-value continuations retain the earliest plan and sort first actions by their IDs")
    func equalValueRetention() throws {
        var request = try RecruitPlannerTests.request(gold: 0)
        let original = try CombatGoldens.input(CombatGoldens.fullGameTurn11).playerBoard.player.heroPowers[0]
        request.recruit!.input.playerBoard.player.heroPowers = [2, 10].map { id in
            var power = original
            power.entityId = id
            power.cardId = "zeroPower"
            power.used = false
            power.locked = 0
            return power
        }
        request.recruit!.powerCosts["zeroPower"] = 0
        var definition = Card(id: "zeroPower", dbfId: 100, name: "Zero power")
        definition.text = "Gain 0 Gold."
        request.recruit!.definitions[definition.id] = definition
        let search = RecruitPlanner.search(request, context: request.recruit!, budget: .init(depth: 2))
        #expect(search.expanded == 4)
        #expect(search.plans.map(\.id) == ["power:10:0:-1", "power:2:0:-1"])
        #expect(search.plans.map(\.value.total) == [0, 0])
        #expect(search.plans.map { $0.state.steps.map(\.entityID) } == [[10], [2]])
        #expect(search.plans.map(\.state.gold) == [0, 0])
        #expect(search.plans.map { $0.state.input.playerBoard.player.heroPowers.filter(\.used).map(\.entityId) }
                == [[10], [2]])
    }
}
