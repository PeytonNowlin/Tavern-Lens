import Foundation
import Testing
import TavernEngine

@Suite("Player action engine integration")
struct PlayerActionEngineTests {
    static func recruiting() -> SyntheticLog {
        var log = LobbySyntheticTests.lobbyGame()
        log.turn(5); log.gameTag("2022", "1")
        log.localTag("RESOURCES", "3")
        log.localTag("NEXT_OPPONENT_PLAYER_ID", "3")
        log.shopCard(435, "BG31_803", position: 1, atk: 2, health: 2)
        log.endTaskList()
        return log
    }

    @Test("Outgoing selection archives the preceding gold before reducer effects and drains once")
    func beforeAction() throws {
        var log = Self.recruiting()
        var engine = TavernEngine()
        for line in log.lines { engine.ingest(line) }
        #expect(try #require(engine.advisorRequest).gold == 3)
        let groupLine = engine.linesRead + 1
        engine.ingest("D 21:10:00.000 GameState.DebugPrintOptions() - id=9")
        engine.ingest("D 21:10:00.000 GameState.DebugPrintOptions() - option 0 type=POWER mainEntity=436 error=NONE errorParam=")
        engine.ingest("D 21:10:01.000 GameState.SendOption() - selectedOption=0 selectedSubOption=-1 selectedTarget=435 selectedPosition=0")
        log = SyntheticLog(); log.localTag("RESOURCES_USED", "3"); log.endTaskList()
        for line in log.lines { engine.ingest(line) }
        let actions = engine.takePlayerActions()
        let action = try #require(actions.first)
        #expect(actions.count == 1 && action.request.gold == 3)
        #expect(action.position.line == groupLine + 2 && action.options?.position?.line == groupLine)
        #expect(action.options?.id == 9 && action.displayedAdvice == nil)
        #expect(try #require(engine.advisorRequest).gold == 0)
        #expect(engine.takePlayerActions().isEmpty)
    }

    @Test("Catch-up selections reconstruct state without becoming new live evidence")
    func catchUp() {
        var engine = TavernEngine(); engine.beginCatchUp()
        for line in Self.recruiting().lines { engine.ingest(line) }
        engine.ingest("D 21:10:01.000 GameState.SendOption() - selectedOption=0 selectedSubOption=-1 selectedTarget=435 selectedPosition=0")
        #expect(engine.takePlayerActions().isEmpty)
        engine.endCatchUp()
        engine.ingest("D 21:10:02.000 GameState.SendOption() - selectedOption=0 selectedSubOption=-1 selectedTarget=435 selectedPosition=0")
        #expect(engine.takePlayerActions().count == 1)
    }
}
