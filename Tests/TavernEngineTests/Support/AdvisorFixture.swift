import Foundation
import HSLog
import Testing
import TavernEngine

/// The advisor's requests in a captured game, asked for at every recruit publish as `LivePipeline`
/// does, and a small deterministic plan for scoring them in tests.
enum AdvisorFixture {
    /// Few simulations (JavaScriptCore interprets under `swift test`), but the full order of passes.
    static let plan = AdvisorPlan(
        seed: 0x19AD_7150, simulations: 100, refineSimulations: 200, refinedGroups: 2, lobbySimulations: 50,
        lobbyGroups: 2
    )

    struct Replay {
        /// The request at each recruit phase's last publish, by BG turn.
        var endOfRecruit: [Int: AdvisorRequest] = [:]
        /// The first request of each recruit phase with a shop and the most gold to spend (the
        /// shop just refilled, before anything was bought): where the advice matters most.
        var mostGold: [Int: AdvisorRequest] = [:]
        /// The line each `mostGold` request was published at.
        var mostGoldLine: [Int: Int] = [:]
        /// Every distinct request, in order.
        var requests: [AdvisorRequest] = []
        /// Publishes outside recruit that had a request (should be none).
        var outsideRecruit = 0
        /// Recruit publishes whose request didn't list the cards the view shows (should be none):
        /// the advisor's indices are the overlay's.
        var mismatches: [String] = []
    }

    /// - Parameter builds: with the build catalog, so requests carry the detected builds.
    static func replay(_ path: String, builds: BuildCatalog? = nil) throws -> Replay {
        var engine = TavernEngine(builds: builds)
        var published = 0
        var replay = Replay()
        try LogFileReader.forEachLine(in: #require(Fixtures.url(path))) { line in
            engine.ingest(line)
            guard engine.timeline.count > published else { return }
            published = engine.timeline.count
            let request = engine.advisorRequest
            if let game = engine.state.game, game.phase == .recruit {
                if let request {
                    let turn = request.preview.bgTurn
                    replay.endOfRecruit[turn] = request
                    if !request.shop.isEmpty, request.gold > replay.mostGold[turn]?.gold ?? -1 {
                        replay.mostGold[turn] = request
                        replay.mostGoldLine[turn] = engine.linesRead
                    }
                    let player = game.player
                    if request.shop.map(\.cardID) != game.shop.cards.map(\.cardID)
                        || request.board.map(\.cardID) != player?.board.map(\.cardID)
                        || request.hand.map(\.cardID) != player?.hand.map(\.cardID)
                        || request.gold != player?.gold.available || request.tier != player?.tier {
                        replay.mismatches.append("line \(engine.linesRead), turn \(turn)")
                    }
                    if replay.requests.last != request { replay.requests.append(request) }
                }
            } else if request != nil {
                replay.outsideRecruit += 1
            }
        }
        return replay
    }

    /// Scores on a simulator of its own (so tests run in parallel), seeded by the plan.
    static func simulate() throws -> AdvisorEvaluation.Simulate {
        let simulator = try CombatGoldens.makeSimulator()
        return AdvisorEvaluation.simulate(on: { simulator })
    }

    static let directory = GoldenHarness.goldenDirectory.appending(path: "Advisor", directoryHint: .isDirectory)

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// Compares `value` to the committed golden `name`, or records it (`TAVERN_RECORD_GOLDENS=1`).
    static func verify<T: Codable & Equatable>(
        _ value: T, golden name: String, sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        var data = try encoder().encode(value)
        data.append(0x0A)
        try #require(!GoldenHarness.containsBattleTag(String(decoding: data, as: UTF8.self)), sourceLocation: sourceLocation)
        let url = directory.appending(path: "\(name).json")
        if GoldenHarness.isRecording {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url)
            return
        }
        let expected = try #require(
            try? JSONDecoder().decode(T.self, from: Data(contentsOf: url)),
            "missing golden \(name); run with TAVERN_RECORD_GOLDENS=1", sourceLocation: sourceLocation
        )
        #expect(expected == value, "differs from golden \(name):\n\(String(decoding: data, as: UTF8.self))",
                sourceLocation: sourceLocation)
    }

    static func load<T: Decodable>(_ type: T.Type, golden name: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(contentsOf: directory.appending(path: "\(name).json")))
    }
}
