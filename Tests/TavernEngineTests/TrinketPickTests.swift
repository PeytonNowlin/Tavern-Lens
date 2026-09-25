import Foundation
import Testing
@testable import TavernEngine
import EntityStore
import PowerParser

@Suite("Trinket offers")
struct TrinketPickTests {
    func card(_ id: String, _ text: String) -> Card {
        var c = Card(id: id, dbfId: 1, name: id)
        c.type = "BATTLEGROUND_TRINKET"; c.text = text; c.cost = 2
        return c
    }

    func game() -> GameView {
        GameView(gameType: "GT_BATTLEGROUNDS", localPlayerID: 1, localHeroCardID: nil, bgTurn: 9,
            phase: .recruit, player: PlayerView(hero: nil, gold: .init(available: 10, thisTurn: 10, used: 0, temporary: 0, cap: 10),
                tier: 4, board: [], hand: []))
    }

    @Test("Board fit changes with the engine; unknown and unaffordable choices do not get fake ranks")
    func ratings() throws {
        let sludge = card("sludge", "Get a Sludge Corrosion. After you discard a card, get a Sludge Corrosion.")
        let end = card("end", "Your end of turn effects trigger an extra time.")
        let unknown = card("unknown", "A completely new effect.")
        var engine = Card(id: "engine", dbfId: 4, name: "Engine")
        engine.text = "Activate (0): Discard a card to get a random Tavern spell."
        var g = game()
        g.player!.board = [CardView(cardID: "engine", kind: .minion, attack: 3, health: 4)]
        let db = CardDB(build: 253216, cards: [sludge, end, unknown, engine])
        let rated = TrinketRater.rate(choiceID: 1, offers: [(1, sludge, 2), (2, end, 2), (3, unknown, 2), (4, sludge, 12)], game: g, cards: db)
        #expect(rated.offers[0].rank == 1)
        #expect(rated.offers[2].score == nil && rated.offers[2].rank == nil)
        #expect(rated.offers[3].rating == "Unavailable" && rated.offers[3].rank == nil)
        engine.text = "At the end of your turn, give your minions +2/+2."
        let changed = TrinketRater.rate(choiceID: 1, offers: [(1, sludge, 2), (2, end, 2)], game: g,
            cards: CardDB(build: 253216, cards: [sludge, end, engine]))
        #expect(changed.offers[1].rank == 1)
    }

    @Test("A trinket offer waits for display and clears on choice or another discover")
    func lifecycle() throws {
        let c = card("sludge", "Get a Sludge Corrosion. After you discard a card, get a Sludge Corrosion.")
        let db = CardDB(build: 253216, cards: [c])
        var tracker = TrinketPickTracker()
        let offer = PowerEvent.entityChoices(.init(id: 10, choiceType: "GENERAL", taskList: 5,
            options: [.init(entityID: 1, cardID: c.id)]))
        tracker.observe(offer)
        #expect(tracker.project(store: EntityStore(), cards: db, game: game(), lastTaskListEnded: 4) == nil)
        #expect(tracker.project(store: EntityStore(), cards: db, game: game(), lastTaskListEnded: 5)?.offers.count == 1)
        tracker.observe(.entitiesChosen(choiceID: 10, chosen: [.init(entityID: 1, cardID: c.id)]))
        #expect(tracker.project(store: EntityStore(), cards: db, game: game(), lastTaskListEnded: 5) == nil)
        tracker.observe(offer)
        tracker.observe(.entityChoices(.init(id: 11, choiceType: "GENERAL", options: [.init(entityID: 2, cardID: "minion") ])))
        #expect(tracker.project(store: EntityStore(), cards: db, game: game(), lastTaskListEnded: 5) == nil)
    }
    @Test("Population ratings require fresh, sufficiently sampled valid data")
    func population() throws {
        let json = #"{"trinketStats":[{"trinketCardId":"unknown","dataPoints":800,"averagePlacement":3.9},{"trinketCardId":"sparse","dataPoints":12,"averagePlacement":1.0}],"lastUpdateDate":"2026-09-25T00:10:27.592Z","dataPoints":812,"timePeriod":"past-three"}"#
        let stats = try JSONDecoder().decode(TrinketStats.self, from: Data(json.utf8))
        let now = try #require(stats.updatedAt)
        #expect(stats.entry("unknown", now: now)?.dataPoints == 800)
        #expect(stats.entry("sparse", now: now) == nil)
        #expect(stats.entry("unknown", now: now.addingTimeInterval(49 * 3600)) == nil)
        let unknown = card("unknown", "New unmodelled effect")
        let db = CardDB(build: 253216, cards: [unknown])
        let rated = TrinketRater.rate(choiceID: 1, offers: [(1, unknown, 2)], game: game(), cards: db, stats: stats, now: now)
        #expect(rated.offers[0].rank == 1 && rated.offers[0].averagePlacement == 3.9)
        #expect(rated.offers[0].reason.contains("baseline only"))
        let stale = TrinketRater.rate(choiceID: 1, offers: [(1, unknown, 2)], game: game(), cards: db,
                                     stats: stats, now: now.addingTimeInterval(49 * 3600))
        #expect(stale.offers[0].rank == nil && stale.offers[0].averagePlacement == nil)
    }

}
