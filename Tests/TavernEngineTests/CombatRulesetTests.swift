import Foundation
import HSLog
import Testing
import TavernEngine

@Suite("Dated simulator compatibility")
struct CombatRulesetTests {
    @Test("The hotfix is selected by log date, with unknown and older dates preserving legacy rules")
    func dateBoundary() {
        let start = BattleRuleset.patch36_6_3Start
        #expect(BattleRuleset.at(date: nil) == nil)
        #expect(BattleRuleset.at(date: start.addingTimeInterval(-1)) == nil)
        #expect(BattleRuleset.at(date: start) == .patch36_6_3)
        #expect(BattleRuleset.at(date: start.addingTimeInterval(86400)) == .patch36_6_3)
    }

    @Test("Combat, previews, and recruit projections carry the same dated rules",
          arguments: ["", "Hearthstone_2026_10_01_15_54_59", "Hearthstone_2026_10_01_15_55_00"])
    func engineTransport(sessionName: String) throws {
        let utc = TimeZone(identifier: "UTC")!
        let session = sessionName.isEmpty ? nil : try #require(LogSession(
            directory: URL(filePath: "/tmp/Logs/\(sessionName)"), timeZone: utc))
        var log = CombatInputSyntheticTests.combat(local: {
            CombatInputSyntheticTests.minion(&$0, 500, "BG36_308",
                controller: SyntheticLog.localPlayerID, position: 1)
        })
        log.time = "15:56:00.0000000"
        log.endCombat(board: [], nextOpponent: 3)
        log.turn(3); log.gameTag("2022", "1"); log.endTaskList()
        var engine = TavernEngine(cards: PoolFixture.cards, session: session, timeZone: utc)
        let initialTime = sessionName.hasSuffix("15_54_59") ? "15:54:59.0000000" : "15:55:00.0000000"
        for line in log.lines {
            engine.ingest(line.replacingOccurrences(of: "21:09:40.3435500", with: initialTime))
        }
        let expected: BattleRuleset? = sessionName.hasSuffix("15_55_00") ? .patch36_6_3 : nil
        let combat = try #require(engine.combatRequests.first)
        #expect(combat.input.gameState.ruleset == expected)
        let preview = try #require(engine.oddsPreview?.input)
        #expect(preview.gameState.ruleset == expected)
        let request = try #require(engine.advisorRequest)
        #expect(request.preview.input?.gameState.ruleset == expected)
        #expect(try #require(request.recruit).input.gameState.ruleset == expected)
    }

    @Test("Legacy encodings and policy fingerprints omit the compatibility field")
    func archives() throws {
        let old = try CombatGoldens.input(CombatGoldens.fullGameTurn11)
        let json = try JSONEncoder().encode(old)
        #expect(!String(decoding: json, as: UTF8.self).contains("ruleset"))
        var current = old; current.gameState.ruleset = .patch36_6_3
        #expect(try JSONDecoder().decode(BattleInput.self, from: JSONEncoder().encode(current)) == current)
        var request = try AdvisorCardTurnPriorTests.request()
        let legacy = AdviceView.fingerprint(of: request, version: 10)
        let latest = AdviceView.fingerprint(of: request, version: 11)
        request.preview.input?.gameState.ruleset = .patch36_6_3
        request.recruit?.input.gameState.ruleset = .patch36_6_3
        #expect(AdviceView.fingerprint(of: request, version: 10) == legacy)
        #expect(AdviceView.fingerprint(of: request, version: 11) != latest)
    }

    @Test("The JavaScriptCore bundle applies current Deity damage without changing a subsequent legacy run")
    func bundledDamage() async throws {
        var input = try CombatGoldens.input(CombatGoldens.fullGameTurn11)
        for side in [\BattleInput.playerBoard, \BattleInput.opponentBoard] {
            input[keyPath: side].player.tavernTier = 1
            input[keyPath: side].player.hpLeft = 40
            input[keyPath: side].player.heroPowers = []
            input[keyPath: side].player.hand = []
            input[keyPath: side].player.secrets = []
            input[keyPath: side].player.trinkets = []
            input[keyPath: side].player.questEntities = []
            input[keyPath: side].player.questRewards = []
            input[keyPath: side].player.questRewardEntities = []
            input[keyPath: side].player.globalInfo = [:]
        }
        var deity = try #require(input.playerBoard.board.first)
        deity.cardId = "BGFYM_000"; deity.attack = 10; deity.health = 10; deity.maxHealth = 10
        deity.taunt = false; deity.divineShield = false; deity.poisonous = false; deity.venomous = false
        deity.reborn = false; deity.stealth = false; deity.windfury = false
        deity.enchantments = []; deity.tags = [:]
        input.playerBoard.board = [deity]; input.opponentBoard.board = []
        input.options.applyDamageCap = false
        input.gameState.anomalies = []; input.gameState.anomalyDbfIds = nil
        let simulator = try CombatGoldens.makeSimulator()
        let budget = SimulationBudget(simulations: 8, maxDurationMilliseconds: 600_000, intermediateResults: 8)
        #expect(try await simulator.simulate(input, budget: budget).averageDamageWon == 4)
        input.gameState.ruleset = .patch36_6_3
        #expect(try await simulator.simulate(input, budget: budget).averageDamageWon == 2)
        input.gameState.ruleset = nil
        #expect(try await simulator.simulate(input, budget: budget).averageDamageWon == 4)
    }
}
