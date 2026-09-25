import Foundation
import Testing
import TavernEngine
import HSLog

/// Opt-in audit against a local match and its exact patch data. No private logs or player names
/// are copied into the repo; this checks the production request-building and evaluation path.
@Suite("Recruit planner match audit")
struct RecruitMatchAuditTests {
    static let log = ProcessInfo.processInfo.environment["TAVERN_ADVISOR_AUDIT_LOG"]
    static let cards = ProcessInfo.processInfo.environment["TAVERN_ADVISOR_AUDIT_CARDS"]

    @Test("Plans on opening and late-game shops use current patch definitions and bounded search",
          .enabled(if: log != nil && cards != nil, "set the local audit log and card-data paths"))
    func match() async throws {
        let db = try CardDB(build: nil, json: Data(contentsOf: URL(filePath: Self.cards!)))
        var engine = TavernEngine(cards: db)
        var selected: [Int: AdvisorRequest] = [:]
        let turns: Set<Int> = [1, 6, 8, 10, 12]
        var trinketChoices: Set<Int> = []
        var sawGiftDefinition = false
        var sawReadyActivate = false
        var published = 0
        try LogFileReader.forEachLine(in: URL(filePath: Self.log!)) { line in
            engine.ingest(line)
            guard engine.timeline.count != published else { return }
            published = engine.timeline.count
            if let pick = engine.state.game?.trinketPick {
                trinketChoices.insert(pick.choiceID)
                #expect(pick.offers.count == 4)
                #expect(pick.offers.contains { $0.rank == 1 })
            }
            if let context = engine.advisorRequest?.recruit {
                if context.definitions["BG36_MidGameEffect_000t74e"] != nil { sawGiftDefinition = true }
                if context.activations?.values.contains(where: \.ready) == true { sawReadyActivate = true }
                for t in context.input.playerBoard.player.trinkets {
                    #expect(context.definitions[t.cardId] != nil)
                }
            }
            guard let game = engine.state.game, game.phase == .recruit, turns.contains(game.bgTurn),
                  let request = engine.advisorRequest, !request.shop.isEmpty,
                  request.gold > (selected[game.bgTurn]?.gold ?? -1) else { return }
            selected[game.bgTurn] = request
        }
        #expect(!selected.isEmpty)
        if Self.log?.contains("2026_09_24_20_17_09") == true {
            #expect(trinketChoices.count == 2)
            #expect(sawGiftDefinition && sawReadyActivate)
        }
        let simulator = try CombatGoldens.makeSimulator()
        let simulate = AdvisorEvaluation.simulate(on: { simulator })
        for turn in selected.keys.sorted() {
            let request = selected[turn]!
            let context = try #require(request.recruit)
            #expect(!context.definitions.isEmpty)
            let start = ContinuousClock.now
            let search = RecruitPlanner.search(request, context: context)
            #expect(search.expanded <= 1800)
            #expect(search.plans.allSatisfy { $0.state.gold >= 0 && $0.state.board.count <= 7 && $0.state.hand.count <= 10 })
            let result = try await AdvisorEvaluation.run(request, plan: .live, limit: 4, simulate: simulate)
            #expect(result.advice.suggestions.allSatisfy { $0.odds == nil && $0.confidence != .high })
            print("Recruit audit turn \(turn): \(search.expanded) nodes, \(search.plans.count) plans, \(search.limitations.count) coverage gaps, \(start.duration(to: .now))")
        }
    }
}
