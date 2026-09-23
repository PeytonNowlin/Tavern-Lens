import Testing
import TavernEngine

/// Seam 1 on synthetic logs: build detection, its turn-to-turn stability, shop highlights,
/// tips and opponents' likely builds, with the shipped build data and no private fixtures.
@Suite("Builds on synthetic logs")
struct BuildSyntheticTests {
    static let local = SyntheticLog.localPlayerID
    static let catalog = BuildFixture.catalog

    // Real 36.6.1 card IDs (research meta-comps §7).
    static let tastyLobster = "BG36_202", titus = "BG25_354", deathstrider = "BG36_208", hyena = "BG36_210"
    static let scorpid = "BG36_209", bananaSlamma = "BG26_802", skitterer = "BG31_809"
    static let forestRover = "BG31_801", buzzingVermin = "BG31_803", sprightlyScarab = "BG27_084"
    /// In the pool, in no build.
    static let filler = "BG36_110"

    /// A game at the first recruit phase with the given local board.
    static func recruiting(board: [String], firstID: Int = 300) -> SyntheticLog {
        var log = SyntheticLog()
        log.createGame(gameType: "GT_BATTLEGROUNDS")
        log.pickHero()
        log.turn(1)
        for (index, cardID) in board.enumerated() {
            log.card(firstID + index, cardID, controller: local, zone: "PLAY", position: index + 1, atk: 2, health: 2)
        }
        log.endTaskList()
        return log
    }

    static func lastGame(_ log: SyntheticLog, catalog: BuildCatalog? = catalog) throws -> GameView {
        try #require(TavernEngine.replay(lines: log.lines, builds: catalog).timeline.last?.state.game)
    }

    static func shown(_ game: GameView) -> [String] { game.builds?.detected.map(\.id) ?? [] }

    @Test("A board with a build's core is detected, with its tips card")
    func detects() throws {
        let game = try Self.lastGame(Self.recruiting(board: [Self.tastyLobster, Self.filler, Self.titus]))
        let build = try #require(game.builds?.detected.first)
        #expect(Self.shown(game) == ["beast_lobster"])
        #expect(build.name == "Beast Lobster" && build.tribes == ["Beast"] && build.source == .firestone)
        #expect(build.coreHave == [Self.tastyLobster, Self.titus])
        #expect(build.coreMissing == [Self.deathstrider, "BG36_204"])
        #expect(build.tips.keyCards == [Self.tastyLobster, Self.deathstrider, Self.titus, "BG36_204"])
        #expect(build.tips.whenToCommit == "Tasty Lobster + Titus Rivendare")
        #expect(build.tips.tip?.hasPrefix("You have to trigger Tasty Lobster") == true)
        #expect(build.tips.difficulty == "Easy" && build.tips.powerLevel == "B" && build.tips.averagePlacement == 3.82)
    }

    @Test("Too little evidence shows nothing: one shared core card, or cards of no build")
    func threshold() throws {
        // Balinda Stonehearth is core to several builds, so alone she says nothing.
        #expect(Self.shown(try Self.lastGame(Self.recruiting(board: ["BG35_883"]))) == [])
        #expect(Self.shown(try Self.lastGame(Self.recruiting(board: [Self.filler]))) == [])
        // A golden counts as its card.
        #expect(Self.shown(try Self.lastGame(Self.recruiting(board: [Self.tastyLobster + "_G"]))) == ["beast_lobster"])
    }

    @Test("Shop cards of a detected build are highlighted by slot, core and add-on apart")
    func shopHighlights() throws {
        var log = Self.recruiting(board: [Self.tastyLobster, Self.titus])
        log.shopCard(400, Self.filler, position: 1)
        log.shopCard(401, Self.hyena, position: 2)
        log.shopCard(402, Self.deathstrider + "_G", position: 3, extra: ["PREMIUM=1"])
        log.shopCard(403, "BG36_303", position: 4, type: "BATTLEGROUND_SPELL")
        log.endTaskList()
        let game = try Self.lastGame(log)
        #expect(game.shop.cards.count == 4)
        #expect(game.builds?.shopHighlights == [
            ShopHighlightView(index: 1, cardID: Self.hyena, role: .addon, buildID: "beast_lobster"),
            ShopHighlightView(index: 2, cardID: Self.deathstrider + "_G", role: .core, buildID: "beast_lobster"),
        ])
        // Nothing is highlighted without a detected build.
        var none = Self.recruiting(board: [Self.filler])
        none.shopCard(401, Self.hyena, position: 1)
        none.endTaskList()
        #expect(try Self.lastGame(none).builds?.shopHighlights == [])
    }

    @Test("A build stays shown for two turns after the turn its cards are sold, then goes")
    func carryOver() throws {
        var log = Self.recruiting(board: [Self.tastyLobster, Self.titus])
        var shownByTurn: [Int: [String]] = [:]
        func record() throws { shownByTurn[try Self.lastGame(log).bgTurn] = Self.shown(try Self.lastGame(log)) }
        try record()
        log.turn(2)
        log.turn(3)
        log.tag(300, "ZONE", "REMOVEDFROMGAME")
        log.tag(301, "ZONE", "REMOVEDFROMGAME")
        log.card(310, Self.filler, controller: Self.local, zone: "PLAY", position: 1)
        log.endTaskList()
        try record()
        for bgTurn in 3...5 {
            log.turn(bgTurn * 2 - 2)
            log.turn(bgTurn * 2 - 1)
            try record()
        }
        #expect(shownByTurn == [
            1: ["beast_lobster"], 2: ["beast_lobster"], 3: ["beast_lobster"], 4: ["beast_lobster"], 5: [],
        ])
    }

    @Test("Within a turn, selling and rebuying a core card doesn't make the build flicker")
    func noFlicker() throws {
        var log = Self.recruiting(board: [Self.tastyLobster, Self.titus])
        log.tag(301, "ZONE", "REMOVEDFROMGAME")
        log.endTaskList()
        log.card(311, Self.titus, controller: Self.local, zone: "PLAY", position: 2)
        log.endTaskList()
        let timeline = TavernEngine.replay(lines: log.lines, builds: Self.catalog).timeline
        let shown = timeline.compactMap(\.state.game).filter { $0.bgTurn == 1 }.map(Self.shown).filter { !$0.isEmpty }
        #expect(!shown.isEmpty && shown.allSatisfy { $0 == ["beast_lobster"] })
    }

    @Test("A build keeps first place until another beats it by the margin")
    func incumbency() throws {
        var log = Self.recruiting(board: [Self.tastyLobster, Self.titus])
        log.turn(2)
        log.turn(3)
        // Beast Beetle edges past Beast Lobster (9 to 8): two core cards it shares with Beast
        // Leviathan and three add-ons. Lobster keeps first place.
        for (offset, card) in [Self.scorpid, Self.bananaSlamma].enumerated() {
            log.card(320 + offset, card, controller: Self.local, zone: "PLAY", position: 3 + offset)
        }
        for (offset, card) in [Self.forestRover, Self.buzzingVermin, Self.sprightlyScarab].enumerated() {
            log.card(330 + offset, card, controller: Self.local, zone: "HAND", position: 1 + offset)
        }
        log.endTaskList()
        #expect(Self.shown(try Self.lastGame(log)) == ["beast_lobster", "beast_beetle"])
        // Its own core card, Turquoise Skitterer, clears the margin.
        log.card(340, Self.skitterer, controller: Self.local, zone: "PLAY", position: 5)
        log.endTaskList()
        #expect(Self.shown(try Self.lastGame(log)) == ["beast_beetle", "beast_lobster"])
    }

    @Test("An opponent's last-seen board gets the build it most looks like, or none")
    func opponentLikelyBuild() throws {
        var log = Self.recruiting(board: [])
        log.sevenOpponents()
        log.startCombat(bgTurn: 1, opponent: 3, name: "Opponent Three", heroID: 500, board: [
            .init(id: 510, cardID: Self.tastyLobster, atk: 3, health: 3),
            .init(id: 511, cardID: Self.deathstrider + "_G", atk: 9, health: 9),
            .init(id: 512, cardID: Self.filler, atk: 1, health: 1),
        ])
        log.endCombat(board: [
            .init(id: 510, cardID: Self.tastyLobster, atk: 3, health: 3),
            .init(id: 511, cardID: Self.deathstrider + "_G", atk: 9, health: 9),
            .init(id: 512, cardID: Self.filler, atk: 1, health: 1),
        ], nextOpponent: 4)
        log.turn(3)
        log.startCombat(bgTurn: 2, opponent: 4, name: "Opponent Four", heroID: 501, board: [
            .init(id: 520, cardID: Self.filler, atk: 1, health: 1),
        ])
        log.endCombat(board: [], nextOpponent: 3)
        log.turn(5)
        let game = try Self.lastGame(log)
        let three = try #require(game.lobby.first { $0.playerID == 3 }?.lastSeenBoard)
        #expect(three.likelyBuild == LikelyBuildView(
            id: "beast_lobster", name: "Beast Lobster", matchedCards: [Self.tastyLobster, Self.deathstrider]
        ))
        #expect(game.lobby.first { $0.playerID == 4 }?.lastSeenBoard?.likelyBuild == nil)
        #expect(game.lobby.first { $0.playerID == 4 }?.lastSeenBoard != nil)
    }

    @Test("Without build data there are no builds; data arriving mid-game turns them on")
    func lateCatalog() throws {
        let log = Self.recruiting(board: [Self.tastyLobster, Self.titus])
        let without = try Self.lastGame(log, catalog: nil)
        #expect(without.builds == nil)
        var engine = TavernEngine()
        for line in log.lines { engine.ingest(line) }
        #expect(engine.state.game?.builds == nil)
        engine.useBuilds(Self.catalog)
        #expect(engine.state.game.map(Self.shown) == ["beast_lobster"])
    }

    @Test("A new game starts detection over")
    func newGame() throws {
        var log = Self.recruiting(board: [Self.tastyLobster, Self.titus])
        log.newGame(seed: 42)
        log.turn(1)
        let game = try Self.lastGame(log)
        #expect(game.bgTurn == 1 && Self.shown(game) == [])
    }
}
