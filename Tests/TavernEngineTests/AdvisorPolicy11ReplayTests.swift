import Foundation
import Testing
import TavernEngine

/// Private evidence stays on the user's machine. The ordinary suite uses synthetic
/// captured outcomes; these opt-in checks compare against actual settled log snapshots.
@Suite("Policy 11 captured effect evidence")
struct AdvisorPolicy11ReplayTests {
    static let directory = ProcessInfo.processInfo.environment["TAVERN_POLICY11_AUDIT_DIAGNOSTICS"]

    static func sample(_ seed: Int, _ turn: Int, _ index: Int) throws -> AdvisorDecision {
        let url = URL(filePath: directory!).appending(path: "game-\(seed)-turn-\(turn).json")
        let diagnostic = try JSONDecoder().decode(AdvisorTurnDiagnostic.self, from: Data(contentsOf: url))
        let decisions = try #require(diagnostic.decisions)
        try #require(decisions.indices.contains(index))
        return decisions[index]
    }

    static func prepared(_ request: AdvisorRequest, dependencies: Bool = false) throws -> AdvisorRequest {
        var request = request
        request.recruit!.evaluationVersion = 11
        if dependencies {
            let build = try #require(request.recruit?.build)
            let url = URL(filePath: directory!).deletingLastPathComponent().appending(path: "CardData/\(build)/cards.json")
            let cards = try CardDB(build: build, json: Data(contentsOf: url))
            let observed = Set((request.board + request.hand + request.shop).map(\.cardID))
            var required: [String] = []
            if !observed.isDisjoint(with: ["BG36_201", "BG36_201_G"]) { required += ["BG36_205", "BG36_205_G"] }
            if !observed.isDisjoint(with: ["BG35_881", "BG35_881_G"]) { required += ["BG35_911"] }
            for id in required {
                request.recruit!.definitions[id] = try #require(cards[id])
            }
        }
        request.builds = AdvisorStrategy.select(request).map { [$0.build] } ?? []
        request.recruit!.strategicEvaluation = true
        return request
    }

    @Test("Archived policy 10 advice, checks and fingerprint remain exact",
          .enabled(if: directory != nil, "set TAVERN_POLICY11_AUDIT_DIAGNOSTICS for local game evidence"))
    func archivedPolicy10() async throws {
        let sample = try Self.sample(2095227427, 6, 2)
        #expect(sample.displayed.plan.version == 10)
        let simulator = try CombatSimulator(); try simulator.loadPinnedCards()
        let replay = try await sample.displayed.replaying(sample.request, simulate: { input, budget, seed in
            try await simulator.simulate(input, budget: budget, seed: seed)
        })
        #expect(replay.advice == sample.displayed.advice)
        #expect(replay.fingerprint == sample.displayed.fingerprint)
        #expect(replay.evaluations == sample.displayed.evaluations && replay.evaluations == 4)
    }

    @Test("Captured Clock and Fortify become exact without changing observed resources",
          .enabled(if: directory != nil, "set TAVERN_POLICY11_AUDIT_DIAGNOSTICS for local game evidence"))
    func clockAndFortify() throws {
        let request = try Self.prepared(Self.sample(2095227427, 6, 2).request)
        let search = RecruitPlanner.search(request, context: request.recruit!)
        let purchases = search.plans.filter { $0.state.steps.contains { $0.kind == .buy } }
        #expect(!purchases.isEmpty && purchases.allSatisfy { $0.projection.limitations.isEmpty })
        #expect(search.baseline.state.gold == request.gold)
        let early = try Self.prepared(Self.sample(2095227427, 3, 6).request)
        let context = early.recruit!, state = RecruitState(request: early, context: context)
        let spell = try #require(early.hand.first { $0.cardID == "BG28_503" })
        let actions = RecruitPlanner.actions(state, context: context).filter { $0.kind == .spell && $0.entityID == spell.entity.entityId }
        #expect(actions.count == 2)
        for action in actions {
            let after = try #require(RecruitPlanner.applying(action, to: state, context: context))
            let beforeCard = try #require(state.board.first { $0.entity.entityId == action.targetID })
            let afterCard = try #require(after.board.first { $0.entity.entityId == action.targetID })
            #expect(afterCard.entity.attack == beforeCard.entity.attack)
            #expect(afterCard.entity.health == beforeCard.entity.health + 3 && afterCard.entity.taunt)
        }
    }

    @Test("Captured normal and golden Lionfish attacks match settled snapshots",
          .enabled(if: directory != nil, "set TAVERN_POLICY11_AUDIT_DIAGNOSTICS for local game evidence"))
    func lionfish() throws {
        for (turn, beforeIndex, afterIndex, sourceID, targetID) in [(4, 6, 8, 1711, 1561), (6, 2, 4, 2612, 3028), (9, 4, 6, 6314, 7272)] {
            let request = try Self.prepared(Self.sample(2095227427, turn, beforeIndex).request, dependencies: true)
            let expected = try Self.sample(2095227427, turn, afterIndex).request
            let context = request.recruit!, state = RecruitState(request: request, context: context)
            let action = try #require(RecruitPlanner.actions(state, context: context).first {
                $0.kind == .activate && $0.entityID == sourceID && $0.targetID == targetID
            })
            let after = try #require(RecruitPlanner.applying(action, to: state, context: context))
            #expect(after.gold == expected.gold)
            #expect(after.shop.map(\.entity.entityId) == expected.shop.map(\.entity.entityId))
            for observed in expected.board {
                let projected = try #require(after.board.first { $0.entity.entityId == observed.entity.entityId })
                #expect(projected.entity.attack == observed.entity.attack && projected.entity.health == observed.entity.health)
            }
        }
        let unsupported = try Self.prepared(Self.sample(2095227427, 11, 0).request, dependencies: true)
        let actions = RecruitPlanner.actions(RecruitState(request: unsupported, context: unsupported.recruit!), context: unsupported.recruit!)
        #expect(actions.allSatisfy { $0.kind != .activate || $0.entityID != 6314 })
    }

    @Test("Captured Prison pending buy and Arcane Absorption reproduce observed stats",
          .enabled(if: directory != nil, "set TAVERN_POLICY11_AUDIT_DIAGNOSTICS for local game evidence"))
    func elementalStatTransfers() throws {
        var request = try Self.prepared(Self.sample(904647525, 13, 5).request, dependencies: true)
        // Power.log records tag 4945=1 after this instance's activation and resets it
        // at the following buy. The old diagnostic schema did not capture that tag.
        request.recruit!.pendingPrisonBuys = [16166: true]
        let context = request.recruit!, state = RecruitState(request: request, context: context)
        let buy = try #require(RecruitPlanner.actions(state, context: context).first { $0.kind == .buy && $0.entityID == 16097 })
        let bought = try #require(RecruitPlanner.applying(buy, to: state, context: context))
        let prisoner = try #require(bought.board.first { $0.entity.entityId == 16166 })
        #expect(prisoner.entity.attack == 1645 && prisoner.entity.health == 1387)
        #expect(bought.pendingPrisonBuys[16166] == false)

        let absorption = try Self.prepared(Self.sample(904647525, 13, 9).request)
        let absorptionContext = absorption.recruit!, absorptionState = RecruitState(request: absorption, context: absorptionContext)
        let spell = try #require(RecruitPlanner.actions(absorptionState, context: absorptionContext).first {
            $0.kind == .spell && $0.entityID == 16363 && $0.targetID == 16166
        })
        let absorbed = try #require(RecruitPlanner.applying(spell, to: absorptionState, context: absorptionContext))
        let after = try #require(absorbed.board.first { $0.entity.entityId == 16166 })
        #expect(after.entity.attack == 1754 && after.entity.health == 1497)
        #expect(absorbed.shop == absorptionState.shop)
    }
}
