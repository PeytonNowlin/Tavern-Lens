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
        lobbyGroups: 2, lobbySweepSimulations: 20
    )

    struct Replay: Sendable {
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

    private struct Key: Hashable, Sendable {
        var path: String
        var builds: Bool
    }

    private static let replays = Memo<Key, Replay>()

    /// Read once per run for every test that looks at it.
    /// - Parameter withBuilds: with `BuildFixture.catalog`, so requests carry the detected builds.
    static func replay(_ path: String, withBuilds: Bool = false) throws -> Replay {
        try replays.value(Key(path: path, builds: withBuilds)) {
            try computeReplay(path, builds: withBuilds ? BuildFixture.catalog : nil)
        }
    }

    private static func computeReplay(_ path: String, builds: BuildCatalog?) throws -> Replay {
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

    /// Scores on a simulator of its own, seeded by the plan. (Its simulations still queue on the one
    /// JavaScript thread every simulator in the process shares.)
    static func simulate() throws -> AdvisorEvaluation.Simulate {
        let simulator = try CombatGoldens.makeSimulator()
        return AdvisorEvaluation.simulate(on: { simulator })
    }

    static let directory = GoldenHarness.goldenDirectory.appending(path: "Advisor", directoryHint: .isDirectory)

    /// Compares `value` to the committed golden `name`, or records it (`TAVERN_RECORD_GOLDENS=1`).
    static func verify<T: Codable & Equatable>(
        _ value: T, golden name: String, sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        try GoldenHarness.verify(value, at: directory.appending(path: "\(name).json"), sourceLocation: sourceLocation)
    }

    static func load<T: Decodable>(_ type: T.Type, golden name: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(contentsOf: directory.appending(path: "\(name).json")))
    }
}
