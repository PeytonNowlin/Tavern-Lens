import Foundation
import Testing
import TavernEngine

@Suite("Live card-turn evidence boundary")
struct CardTurnEvidenceEngineTests {
    @Test("Power.log turns map to exact recruit turns; turn four evidence remains inactive",
          arguments: [1, 3, 5, 7])
    func turnMapping(rawTurn: Int) throws {
        let now = Date(), recruitTurn = (rawTurn + 1) / 2
        var card = Card(id: "opener", dbfId: 1, name: "Opener")
        card.type = "MINION"; card.techLevel = 1; card.isBattlegroundsPoolMinion = true
        let cards = CardDB(build: 251952, cards: [card])
        let stats = CardTurnStats(lastUpdateDate: ISO8601DateFormatter().string(from: now),
            dataPoints: 1000, timePeriod: "last-patch", cardStats: [
                .init(cardId: card.id, totalPlayed: 1000, averagePlacement: 3, averagePlacementOther: 5,
                    turnStats: (1...4).map {
                        .init(turn: $0, totalPlayed: 250, totalOther: 250, averagePlacement: 3, averagePlacementOther: 5)
                    })
            ])
        var log = LobbySyntheticTests.lobbyGame()
        log.turn(rawTurn); log.gameTag("2022", "1"); log.localTag("NEXT_OPPONENT_PLAYER_ID", "3")
        log.shopCard(400, card.id, position: 1, atk: 2, health: 2); log.endTaskList()
        var setup = EngineSetup(cards: cards, pool: MinionPool.compose(cards: cards, metaPeriod: nil, overrides: nil))
        setup.cardTurnStats = stats; setup.cardTurnStatsCheckedAt = now
        var engine = TavernEngine(setup: setup)
        for line in log.lines { engine.ingest(line) }
        let request = try #require(engine.advisorRequest)
        #expect(request.preview.bgTurn == recruitTurn)
        if recruitTurn <= 3 {
            #expect(request.cardTurnStats?.cardStats.first?.turnStats.map(\.turn) == [recruitTurn])
        } else { #expect(request.cardTurnStats == nil) }
    }

    @Test("Requests capture only active offered minions for an exact card-data build")
    func subset() throws {
        let now = Date()
        var active = Card(id: "active", dbfId: 1, name: "Active")
        active.type = "MINION"; active.techLevel = 1; active.isBattlegroundsPoolMinion = true
        var inactive = active; inactive.id = "inactive"; inactive.dbfId = 2; inactive.isBattlegroundsPoolMinion = false
        let cards = CardDB(build: 251952, cards: [active, inactive])
        let pool = MinionPool.compose(cards: cards, metaPeriod: nil, overrides: nil)
        let stats = CardTurnStats(lastUpdateDate: ISO8601DateFormatter().string(from: now),
            dataPoints: 1000, timePeriod: "last-patch", cardStats: ["active", "inactive", "unoffered"].map {
                .init(cardId: $0, totalPlayed: 500, averagePlacement: 3, averagePlacementOther: 5,
                    turnStats: [.init(turn: 3, totalPlayed: 500, totalOther: 500, averagePlacement: 3, averagePlacementOther: 5)])
            })
        var log = LobbySyntheticTests.lobbyGame()
        log.turn(5); log.gameTag("2022", "1"); log.localTag("NEXT_OPPONENT_PLAYER_ID", "3")
        log.shopCard(400, "active", position: 1, atk: 2, health: 2)
        log.shopCard(401, "inactive", position: 2, atk: 2, health: 2); log.endTaskList()
        var setup = EngineSetup(cards: cards, pool: pool)
        setup.cardTurnStats = stats; setup.cardTurnStatsCheckedAt = now
        var engine = TavernEngine(setup: setup)
        for line in log.lines { engine.ingest(line) }
        let request = try #require(engine.advisorRequest)
        #expect(request.cardTurnStats?.cardStats.map(\.cardId) == ["active"])
        #expect(request.cardTurnStatsCheckedAt == now)
        #expect(engine.advisorRequest == request, "reading an unchanged state must not change the evidence clock")
        engine.usePool(MinionPool.compose(cards: CardDB(build: 253216, cards: [active]), metaPeriod: nil, overrides: nil))
        #expect(engine.advisorRequest?.cardTurnStats == nil)
        engine.usePool(pool)
        engine.useCardTurnStats(stats, checkedAt: now.addingTimeInterval(-49 * 3600))
        #expect(engine.advisorRequest?.cardTurnStats == nil)
        var old = stats; old.lastUpdateDate = ISO8601DateFormatter().string(from: now.addingTimeInterval(-49 * 3600))
        engine.useCardTurnStats(old, checkedAt: now)
        #expect(engine.advisorRequest?.cardTurnStats == nil)
    }
}
