import Foundation
import Testing
import TavernEngine

/// Seam 1 with pinned card data: card IDs resolve to names in the replayed timeline
/// and the end-of-log entity table, and tag numbers print as names.
@Suite("Replay with card data")
struct CardNameReplayTests {
    /// A trimmed, real HearthstoneJSON `cards.json` (build 251952), committed so tests need no network.
    static let cards: CardDB = {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/HearthstoneJSON/cards.251952.trimmed.json")
        // swiftlint:disable:next force_try
        return try! CardDB(build: 251_952, json: Data(contentsOf: url))
    }()

    @Test("The local hero's name appears once the pick resolves")
    func heroName() throws {
        let result = TavernEngine.replay(lines: SyntheticLog.soloGame(bgTurns: 2).lines, cards: Self.cards)
        let names = result.timeline.map { $0.state.game?.localHeroName }
        #expect(names.first == .some(nil))
        #expect(names.last == "George the Fallen")
        #expect(result.timeline.last?.state.game?.localHeroCardID == "TB_BaconShop_HERO_15")
    }

    @Test("Without card data, or for a card it doesn't have, the name is left out")
    func noName() {
        let plain = TavernEngine.replay(lines: SyntheticLog.soloGame(bgTurns: 1).lines)
        #expect(plain.timeline.allSatisfy { $0.state.game?.localHeroName == nil })

        var log = SyntheticLog()
        log.createGame(gameType: "GT_BATTLEGROUNDS")
        log.pickHero(cardID: "BG99_HERO_FROM_THE_FUTURE")
        let unknown = TavernEngine.replay(lines: log.lines, cards: Self.cards)
        #expect(unknown.timeline.last?.state.game?.localHeroCardID == "BG99_HERO_FROM_THE_FUTURE")
        #expect(unknown.timeline.last?.state.game?.localHeroName == nil)
    }

    @Test("The entity table resolves card names and tag names, keeping unknown tags as numbers")
    func entityTable() throws {
        var log = SyntheticLog.soloGame(bgTurns: 1, complete: false)
        log.power("TAG_CHANGE Entity=GameEntity tag=987654 value=3 ")
        log.power("TAG_CHANGE Entity=GameEntity tag=1440 value=2 ")
        log.endTaskList()
        let result = TavernEngine.replay(lines: log.lines, cards: Self.cards)

        let hero = try #require(result.entities.first { $0.id == SyntheticLog.pickedHeroID })
        #expect(hero.cardName == "George the Fallen")
        #expect(hero.tags.contains(.init(tag: "ZONE", number: 49, value: "PLAY")))

        let placeholder = try #require(result.entities.first { $0.id == SyntheticLog.placeholderHeroID })
        #expect(placeholder.cardName == "BaconPHhero")

        let game = try #require(result.entities.first { $0.id == SyntheticLog.gameEntityID })
        #expect(game.cardName == nil)
        #expect(game.tags.contains(.init(tag: "TECH_LEVEL", number: 1440, value: "2")))
        #expect(game.tags.contains(.init(tag: "987654", number: 987_654, value: "3")))
        #expect(game.tags.contains { $0.tag == "GAME_SEED" })
    }

    @Test(
        "Full game: George the Fallen by name",
        .enabled(if: Fixtures.isAvailable(Fixtures.fullGame), "private fixture log not present")
    )
    func fullGame() throws {
        let result = try TavernEngine.replay(fileAt: #require(Fixtures.url(Fixtures.fullGame)), cards: Self.cards)
        #expect(result.timeline.last?.state.game?.localHeroName == "George the Fallen")
        #expect(result.entities.contains { $0.cardName == "George the Fallen" })
        // Every tag name the client printed is in the pinned enums.
        let tags = result.entities.flatMap(\.tags)
        #expect(!tags.isEmpty)
        #expect(Set(tags.filter { $0.number == nil }.map(\.tag)).sorted() == [])
    }
}
