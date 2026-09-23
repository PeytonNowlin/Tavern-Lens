import Foundation
import Testing
import TavernEngine

/// Seam 1 on the captured games: build detection per turn (golden), its stability, shop
/// highlights on the right slots, and opponents' likely builds, with the shipped build data
/// and the 36.6.1 pool.
@Suite("Builds on captured games")
struct BuildFixtureTests {
    static let bothFixtures = Fixtures.isAvailable(Fixtures.fullGame) && Fixtures.isAvailable(Fixtures.truncatedGame)

    static func replay(_ fixture: String) throws -> ReplayResult {
        try FixtureReplays.result(fixture, .builds)
    }

    /// What a checkpoint's builds look like in the golden: compact, and without names.
    struct Checkpoint: Codable, Equatable {
        struct Detected: Codable, Equatable {
            var id: String
            var coreHave: [String]
            var addonsHave: [String]
        }

        var detected: [Detected]
        var shop: [String]
        var shopHighlights: [ShopHighlightView]
        /// PlayerID -> likely build of their last-seen board.
        var opponents: [String: LikelyBuildView]
    }

    struct Golden: Codable, Equatable {
        var catalog: [String]
        var checkpoints: [String: Checkpoint]
    }

    /// End of each recruit phase, and the end of the log.
    static func golden(_ result: ReplayResult) -> Golden {
        var checkpoints: [String: Checkpoint] = [:]
        let lastTurn = result.timeline.compactMap(\.state.game?.bgTurn).max() ?? 0
        var picks: [(String, TimelineEntry?)] = (1...max(1, lastTurn)).map { turn in
            ("turn:\(turn):recruit:end", result.timeline.last { $0.state.game?.bgTurn == turn && $0.state.game?.phase == .recruit })
        }
        picks.append(("last", result.timeline.last))
        for (key, entry) in picks {
            guard let game = entry?.state.game else { continue }
            checkpoints[key] = Checkpoint(
                detected: (game.builds?.detected ?? []).map {
                    .init(id: $0.id, coreHave: $0.coreHave, addonsHave: $0.addonsHave)
                },
                shop: game.shop.cards.map(\.cardID),
                shopHighlights: game.builds?.shopHighlights ?? [],
                opponents: Dictionary(uniqueKeysWithValues: game.lobby.compactMap { entry in
                    entry.lastSeenBoard?.likelyBuild.map { ("P\(entry.playerID)", $0) }
                })
            )
        }
        return Golden(catalog: BuildFixture.catalog.builds.map(\.id), checkpoints: checkpoints)
    }

    static func verify(_ result: ReplayResult, golden name: String) throws {
        let actual = golden(result)
        let url = GoldenHarness.goldenDirectory.appending(path: "\(name).json")
        guard let (expected, _) = try GoldenHarness.recordOrLoad(actual, at: url) else { return }
        #expect(expected.catalog == actual.catalog)
        for key in Set(expected.checkpoints.keys).union(actual.checkpoints.keys).sorted() {
            #expect(expected.checkpoints[key] == actual.checkpoints[key], "checkpoint \(key) differs from golden '\(name)'")
        }
    }

    @Test("Full game: the builds per turn match the golden", .enabled(if: Fixtures.isAvailable(Fixtures.fullGame)))
    func fullGameGolden() throws {
        let result = try Self.replay(Fixtures.fullGame)
        try Self.verify(result, golden: "builds-full-game")
        // The player drifts into Aberration Discard from turn 7 and adds Tavern Spells later.
        let golden = Self.golden(result)
        #expect(golden.checkpoints["turn:6:recruit:end"]?.detected == [])
        #expect(golden.checkpoints["turn:7:recruit:end"]?.detected.first?.id == "aberration_discard_deity")
        #expect(golden.checkpoints["turn:12:recruit:end"]?.detected.map(\.id).sorted()
            == ["aberration_discard_deity", "aberration_spell_deity"])
    }

    @Test("Truncated game: the builds per turn match the golden", .enabled(if: Fixtures.isAvailable(Fixtures.truncatedGame)))
    func truncatedGameGolden() throws {
        let result = try Self.replay(Fixtures.truncatedGame)
        try Self.verify(result, golden: "builds-truncated-game")
        // Five turns of Aberration fodder and tempo minions: no build yet.
        #expect(Self.golden(result).checkpoints.values.allSatisfy { $0.detected.isEmpty })
    }

    /// The first detected build at each turn's end of recruit.
    static func primaries(_ result: ReplayResult) -> [String?] {
        let lastTurn = result.timeline.compactMap(\.state.game?.bgTurn).max() ?? 0
        return (1...max(1, lastTurn)).map { turn in
            result.timeline.last { $0.state.game?.bgTurn == turn && $0.state.game?.phase == .recruit }?
                .state.game?.builds?.detected.first?.id
        }
    }

    @Test("Detection is stable turn to turn: no build comes back after being replaced, no turn flickers",
          .enabled(if: bothFixtures, "private fixture logs not present"),
          arguments: [Fixtures.fullGame, Fixtures.truncatedGame])
    func stable(fixture: String) throws {
        let result = try Self.replay(fixture)
        let primaries = Self.primaries(result).compactMap { $0 }
        var runs: [String] = []
        for id in primaries where runs.last != id { runs.append(id) }
        #expect(Set(runs).count == runs.count, "a replaced build came back: \(runs)")
        #expect(runs.count <= 2, "the first build changed too often: \(runs)")
        // Within a recruit phase, the first build changes at most once.
        let games = result.timeline.compactMap(\.state.game).filter { $0.phase == .recruit }
        for turn in Set(games.map(\.bgTurn)) {
            var seen: [String] = []
            for id in games.filter({ $0.bgTurn == turn }).compactMap({ $0.builds?.detected.first?.id }) where seen.last != id {
                seen.append(id)
            }
            #expect(seen.count <= 2, "turn \(turn) flickered: \(seen)")
        }
    }

    @Test("Every highlight is a real shop slot holding a core or add-on card of a detected build",
          .enabled(if: bothFixtures, "private fixture logs not present"),
          arguments: [Fixtures.fullGame, Fixtures.truncatedGame])
    func highlightsMatchShop(fixture: String) throws {
        let catalog = BuildFixture.catalog
        var highlighted = 0
        for game in try Self.replay(fixture).timeline.compactMap(\.state.game) {
            let highlights = game.builds?.shopHighlights ?? []
            if game.phase != .recruit { #expect(highlights.isEmpty) }
            for highlight in highlights {
                highlighted += 1
                try #require(game.shop.cards.indices.contains(highlight.index))
                #expect(game.shop.cards[highlight.index].cardID == highlight.cardID)
                let build = try #require(game.builds?.detected.first { $0.id == highlight.buildID })
                let base = catalog.baseCardID(highlight.cardID)
                let definition = try #require(catalog.build(build.id))
                #expect(highlight.role == .core ? definition.core.contains(base) : definition.addons.contains(base))
            }
            // Each slot at most once, in slot order.
            #expect(highlights.map(\.index) == highlights.map(\.index).sorted() && Set(highlights.map(\.index)).count == highlights.count)
        }
        if fixture == Fixtures.fullGame { #expect(highlighted > 0) }
    }

    @Test("Opponents whose board matches a build show it; its cards were on that board",
          .enabled(if: Fixtures.isAvailable(Fixtures.fullGame)))
    func opponentLikelyBuilds() throws {
        let result = try Self.replay(Fixtures.fullGame)
        let catalog = BuildFixture.catalog
        var shown: Set<String> = []
        for game in result.timeline.compactMap(\.state.game) {
            for entry in game.lobby {
                guard let board = entry.lastSeenBoard, let likely = board.likelyBuild else { continue }
                shown.insert("P\(entry.playerID)=\(likely.id)")
                let onBoard = Set(board.cards.map { catalog.baseCardID($0.cardID) })
                #expect(!likely.matchedCards.isEmpty && likely.matchedCards.allSatisfy(onBoard.contains))
                #expect(!entry.isLocal)
            }
        }
        // P7's board from turn 8: Vicious Mindslasher and Unwilling Slacker.
        #expect(shown.contains("P7=aberration_spell_deity"))
    }

    @Test("No build is shown for a tribe ruled out of the lobby",
          .enabled(if: bothFixtures, "private fixture logs not present"),
          arguments: [Fixtures.fullGame, Fixtures.truncatedGame])
    func respectsLobbyTribes(fixture: String) throws {
        let catalog = BuildFixture.catalog
        for game in try Self.replay(fixture).timeline.compactMap(\.state.game) {
            let absent = Set((game.tribes?.tribes ?? []).filter { $0.confidence == .absent }.map(\.tribe))
            let ids = (game.builds?.detected.map(\.id) ?? []) + game.lobby.compactMap { $0.lastSeenBoard?.likelyBuild?.id }
            for id in ids {
                let tribes = try #require(catalog.build(id)).tribes.compactMap(\.name)
                #expect(tribes.isEmpty || !tribes.allSatisfy(absent.contains), "\(id) shown though \(tribes) are out of the lobby")
            }
        }
    }
}
