import Foundation
import HSData
import Testing

/// Firestone's hero stats: the committed trimmed files decode, and the store fetches each
/// window with its ETag, keeps the last good copy when a fetch fails or looks partial, and
/// works offline from the cache. Runs against a temporary cache directory and a stubbed
/// source (no network).
@Suite("Hero stats")
final class HeroStatsTests {
    /// Answers per window, and records the ETags it was sent.
    final class StubSource: HeroStatsSource, @unchecked Sendable {
        private let lock = NSLock()
        private var answers: [HeroStatsWindow: Result<HeroStatsResponse, any Error>] = [:]
        private var _etags: [HeroStatsWindow: [String?]] = [:]

        func answer(_ window: HeroStatsWindow, _ result: Result<HeroStatsResponse, any Error>) {
            lock.withLock { answers[window] = result }
        }

        func answerAll(_ result: (HeroStatsWindow) -> Result<HeroStatsResponse, any Error>) {
            for window in HeroStatsWindow.allCases { answer(window, result(window)) }
        }

        func etagsSent(_ window: HeroStatsWindow) -> [String?] { lock.withLock { _etags[window] ?? [] } }

        func fetch(window: HeroStatsWindow, mmrPercentile: Int, etag: String?) async throws -> HeroStatsResponse {
            try lock.withLock {
                _etags[window, default: []].append(etag)
                guard let answer = answers[window] else { throw HeroStatsFetchError.httpStatus(503) }
                return try answer.get()
            }
        }
    }

    struct Offline: Error {}

    static let fixtures = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures/Firestone", directoryHint: .isDirectory)

    static func fixture(_ window: HeroStatsWindow) throws -> Data {
        try Data(contentsOf: fixtures.appending(path: "hero-stats.mmr-100.\(window.rawValue).trimmed.json"))
    }

    /// A file of `count` heroes averaging `average`.
    static func file(heroes count: Int, average: Double, dataPoints: Int = 100_000) throws -> Data {
        let stats = (0..<count).map { FirestoneHeroStat(heroCardId: "BG_H\($0)", dataPoints: 1000, averagePosition: average) }
        return try JSONEncoder().encode(FirestoneHeroStatsFile(
            lastUpdateDate: Date(timeIntervalSince1970: 1_790_122_226), dataPoints: dataPoints, heroStats: stats
        ))
    }

    let directory: URL
    let now = Date(timeIntervalSince1970: 1_790_140_000)  // 2026-09-23 05:06Z

    init() {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "TavernLensHeroStatsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func store(_ source: StubSource) -> HeroStatsStore {
        HeroStatsStore(cache: HeroStatsCache(directory: directory), source: source)
    }

    @Test("The trimmed Firestone fixtures decode, with the update date, games and placement shares")
    func decodesFixture() throws {
        let three = try FirestoneHeroStatsFile(json: Self.fixture(.pastThree))
        #expect(three.heroStats.count == 118)
        #expect(three.isUsable)
        #expect(three.dataPoints == 156_829)
        #expect(abs((three.lastUpdateDate?.timeIntervalSince1970 ?? 0) - 1_790_122_226.557) < 0.001)
        let george = try #require(three.heroStats.first { $0.heroCardId == "TB_BaconShop_HERO_15" })
        #expect(george.dataPoints == 1464)
        #expect(george.averagePosition == 3.92)
        #expect(george.placements.count == 8)
        #expect(abs(george.placements.reduce(0, +) - 100) < 0.1)
        #expect(george.tribeStats.count == 11)
        // No Firestone key is a skin.
        #expect(!three.heroStats.contains { $0.heroCardId.contains("_SKIN_") })
    }

    @Test("Firestone's URLs use the past-three / past-seven / last-patch slugs")
    func urls() {
        #expect(FirestoneHeroStatsSource.url(window: .pastThree, mmrPercentile: 100).absoluteString
            == "https://static.zerotoheroes.com/api/bgs/hero-stats/mmr-100/past-three/overview-from-hourly.gz.json")
        #expect(FirestoneHeroStatsSource.url(window: .pastSeven, mmrPercentile: 100).absoluteString.contains("/past-seven/"))
        #expect(FirestoneHeroStatsSource.url(window: .lastPatch, mmrPercentile: 25).absoluteString.contains("/mmr-25/last-patch/"))
    }

    @Test("Downloaded and cached with its ETag; the next load sends the ETag, and a 304 keeps the cached copy")
    func etags() async throws {
        let source = StubSource()
        // Every window gets the full past-three file (the other trimmed files are too small to pass as usable).
        source.answerAll { .success(.body(try! Self.fixture(.pastThree), etag: "\"etag-\($0.rawValue)\"")) }
        let first = await store(source).load(now: now)
        #expect(first.origins.values.allSatisfy { $0 == .downloaded })
        #expect(!first.hadFailures)
        #expect(first.stats.stat(for: "TB_BaconShop_HERO_15")?.window == .pastThree)
        #expect(source.etagsSent(.pastThree) == [nil])

        source.answerAll { _ in .success(.notModified) }
        let second = await store(source).load(now: now.addingTimeInterval(6 * 3600))
        #expect(source.etagsSent(.pastThree) == [nil, "\"etag-past-three\""])
        #expect(second.origins[.pastThree] == .notModified)
        #expect(second.stats.stat(for: "TB_BaconShop_HERO_15")?.stat.averagePosition == 3.92)
        #expect(second.stats == first.stats)
    }

    @Test("A failed fetch keeps the last good copy (stale); with nothing cached the window is missing")
    func offline() async throws {
        let source = StubSource()
        source.answerAll { _ in .failure(Offline()) }
        let empty = await store(source).load(now: now)
        #expect(empty.stats.heroCardIDs.isEmpty)
        #expect(empty.origins.values.allSatisfy { if case .missing = $0 { true } else { false } })

        source.answerAll { _ in .success(.body(try! Self.fixture(.pastThree), etag: nil)) }
        _ = await store(source).load(now: now)
        source.answerAll { _ in .failure(Offline()) }
        let stale = await store(source).load(now: now.addingTimeInterval(3600))
        #expect(stale.hadFailures)
        #expect(stale.origins.values.allSatisfy { if case .stale = $0 { true } else { false } })
        #expect(stale.stats.stat(for: "BG35_HERO_001")?.stat.dataPoints == 2877)
        // The cache alone, without the network.
        #expect(store(source).cached() == stale.stats)
    }

    @Test("An empty or partial file (under 50 heroes, or no games) doesn't replace the last good copy")
    func partialFileRejected() async throws {
        let source = StubSource()
        source.answer(.pastThree, .success(.body(try Self.file(heroes: 60, average: 4.0), etag: "\"good\"")))
        _ = await store(source).load(now: now)

        source.answer(.pastThree, .success(.body(try Self.file(heroes: 10, average: 1.0), etag: "\"partial\"")))
        let partial = await store(source).load(now: now)
        #expect(partial.origins[.pastThree] == .stale(reason: "the stats file was empty or partial"))
        #expect(partial.stats.stat(for: "BG_H0")?.stat.averagePosition == 4.0)

        source.answer(.pastThree, .success(.body(try Self.file(heroes: 60, average: 1.0, dataPoints: 0), etag: nil)))
        let noGames = await store(source).load(now: now)
        #expect(noGames.stats.stat(for: "BG_H0")?.stat.averagePosition == 4.0)
        // The good copy's ETag is still the one sent.
        #expect(source.etagsSent(.pastThree).last == "\"good\"")

        source.answer(.pastThree, .success(.body(Data("<html>oops</html>".utf8), etag: nil)))
        let garbage = await store(source).load(now: now)
        #expect(garbage.stats.stat(for: "BG_H0")?.stat.averagePosition == 4.0)
    }

    @Test("A hero comes from past-three with 300+ games, else past-seven, else last-patch, else where it has most games")
    func windowPreference() throws {
        func file(_ rows: [(String, Int, Double)]) -> FirestoneHeroStatsFile {
            FirestoneHeroStatsFile(lastUpdateDate: nil, dataPoints: 1, heroStats: rows.map {
                FirestoneHeroStat(heroCardId: $0.0, dataPoints: $0.1, averagePosition: $0.2)
            })
        }
        let set = HeroStatsSet(files: [
            .pastThree: file([("A", 300, 1), ("B", 299, 1), ("C", 10, 1), ("E", 50, 1)]),
            .pastSeven: file([("B", 400, 2), ("C", 20, 2), ("E", 250, 2)]),
            .lastPatch: file([("C", 500, 3), ("D", 5, 3), ("E", 100, 3)]),
        ])
        #expect(set.stat(for: "A")?.window == .pastThree)
        #expect(set.stat(for: "B")?.window == .pastSeven)
        #expect(set.stat(for: "C")?.window == .lastPatch)
        #expect(set.stat(for: "D")?.window == .lastPatch)
        #expect(set.stat(for: "E")?.window == .pastSeven)
        #expect(set.stat(for: "Z") == nil)
    }

    @Test("Rows that don't decode are skipped, not fatal")
    func lenientDecoding() throws {
        let json = """
        {"lastUpdateDate":"2026-09-23T00:10:26Z","dataPoints":5,"heroStats":[
          {"heroCardId":"BG_OK","dataPoints":5,"averagePosition":4.5,"placementDistribution":[{"rank":1,"percentage":20}],
           "tribeStats":[{"tribe":17,"dataPoints":3,"dataPointsOnMissingTribe":2,"impactAveragePosition":0.1},{"tribe":"x"}],
           "somethingNew":[1,2,3]},
          {"heroCardId":"BG_BAD","averagePosition":"n/a"}
        ]}
        """
        let file = try FirestoneHeroStatsFile(json: Data(json.utf8))
        #expect(file.heroStats.map(\.heroCardId) == ["BG_OK"])
        #expect(file.heroStats.first?.tribeStats.count == 1)
        #expect(file.heroStats.first?.winPercent == 20)
        #expect(file.lastUpdateDate == Date(timeIntervalSince1970: 1_790_122_226))
    }
}
