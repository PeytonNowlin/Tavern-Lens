import Foundation
import HSData
import Testing

/// Firestone's comp stats and strategies: fetched at most every 6 hours with the cached
/// ETag, cached (the comp stats in derived form), and falling back to the last good copy and
/// then the bundled one. Runs against a temporary directory and a stubbed source (no network).
@Suite("Build data")
final class BuildDataStoreTests {
    final class StubSource: BuildDataSource, @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [BuildDataFile: Result<BuildDataFetch, any Error>]
        private var _requests: [(BuildDataFile, String?)] = []

        init(_ responses: [BuildDataFile: Result<BuildDataFetch, any Error>]) { self.responses = responses }

        var requests: [(file: BuildDataFile, etag: String?)] { lock.withLock { _requests.map { ($0.0, $0.1) } } }
        func respond(_ file: BuildDataFile, _ response: Result<BuildDataFetch, any Error>) {
            lock.withLock { responses[file] = response }
        }

        func fetch(_ file: BuildDataFile, etag: String?) async throws -> BuildDataFetch {
            try lock.withLock {
                _requests.append((file, etag))
                return try (responses[file] ?? .failure(BuildDataError.httpStatus(503))).get()
            }
        }
    }

    let directory: URL
    let now = Date(timeIntervalSince1970: 1_790_140_000)  // 2026-09-23 05:06Z

    init() {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "TavernLensBuildDataTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    static let strategies = Data("""
    [{"compId":"","name":"","patchNumber":"","cards":[],"tips":[]},
     {"compId":"beast_lobster","name":"Beast Lobster","patchNumber":248022,"difficulty":"Easy","powerLevel":"B",
      "cards":[{"cardId":"#N/A","name":"Tasty Lobster","status":"CORE"}],
      "tips":[{"tip":"Trigger it","whenToCommit":"Lobster + Titus"}]}]
    """.utf8)

    func store(_ source: StubSource) -> BuildDataStore {
        BuildDataStore(cache: BuildDataCache(directory: directory), source: source)
    }

    func ok() -> StubSource {
        StubSource([
            .compStats: .success(.data(FirestoneCompStatsTests.raw, etag: "\"c1\"")),
            .strategies: .success(.data(Self.strategies, etag: "\"s1\"")),
        ])
    }

    @Test("Fetched and cached (comp stats reduced), then served from the cache for 6 hours")
    func downloadThenCache() async throws {
        let source = ok()
        let first = await store(source).load(now: now, bundledStats: nil, bundledStrategies: nil)
        #expect(first.statsOrigin == .downloaded && first.strategiesOrigin == .downloaded)
        #expect(first.stats?.comps.first?.boardsWithCard["BG36_202"] == 2)
        #expect(first.strategies?.comps.map(\.compId) == ["beast_lobster"])
        #expect(source.requests.map(\.etag) == [nil, nil])
        // The cache holds the reduced form, not Firestone's raw file.
        let cached = try Data(contentsOf: directory.appending(path: "comp-stats.json"))
        #expect(try FirestoneCompStats(json: cached) == first.stats)
        #expect(!first.provenance(overridesPatch: "36.6.1").isStale)

        let second = await store(source).load(now: now.addingTimeInterval(5 * 3600), bundledStats: nil, bundledStrategies: nil)
        #expect(second.statsOrigin == .cache && second.strategiesOrigin == .cache)
        #expect(second.stats == first.stats && second.strategies == first.strategies)
        #expect(source.requests.count == 2)
    }

    @Test("After 6 hours the fetch is conditional; a 304 keeps the cached copy and restarts the clock")
    func conditionalRefresh() async {
        let source = ok()
        _ = await store(source).load(now: now, bundledStats: nil, bundledStrategies: nil)
        source.respond(.compStats, .success(.notModified))
        source.respond(.strategies, .success(.notModified))
        let later = now.addingTimeInterval(7 * 3600)
        let refreshed = await store(source).load(now: later, bundledStats: nil, bundledStrategies: nil)
        #expect(refreshed.statsOrigin == .cache && refreshed.strategiesOrigin == .cache)
        #expect(refreshed.stats?.timePeriod == "past-three")
        #expect(source.requests.suffix(2).map(\.etag) == ["\"c1\"", "\"s1\""])
        let again = await store(source).load(now: later.addingTimeInterval(3600), bundledStats: nil, bundledStrategies: nil)
        #expect(again.statsOrigin == .cache)
        #expect(source.requests.count == 4)
    }

    @Test("A failed fetch serves the last good copy as stale; with nothing cached, the bundled copy")
    func fallbacks() async throws {
        let bundledStats = FirestoneCompStats.bundled()
        let bundledStrategies = FirestoneStrategies.bundled()
        let failing = StubSource([:])
        let empty = await store(failing).load(now: now, bundledStats: bundledStats, bundledStrategies: bundledStrategies)
        #expect(empty.statsOrigin == .bundled(reason: "Firestone answered HTTP 503"))
        #expect(empty.stats?.timePeriod == "last-patch")
        #expect(empty.strategiesOrigin?.isStale == true && empty.strategies?.comps.count == 18)
        #expect(empty.provenance(overridesPatch: nil).isStale)

        _ = await store(ok()).load(now: now, bundledStats: bundledStats, bundledStrategies: bundledStrategies)
        let stale = await store(failing).load(
            now: now.addingTimeInterval(7 * 3600), bundledStats: nil, bundledStrategies: bundledStrategies
        )
        #expect(stale.statsOrigin == .stale(reason: "Firestone answered HTTP 503"))
        #expect(stale.stats?.timePeriod == "past-three")
        #expect(stale.strategies?.comps.map(\.compId) == ["beast_lobster"])

        let nothing = await store(StubSource([:])).load(
            now: now.addingTimeInterval(7 * 3600), bundledStats: nil, bundledStrategies: nil
        )
        #expect(nothing.stats != nil)  // the stale cache is still there
    }

    @Test("A cached comp-stats copy older than the bundled one loses to it; missing files (403) fall back")
    func staleVersusBundled() async throws {
        var old = try FirestoneCompStats.derive(fromFirestone: FirestoneCompStatsTests.raw)
        old.lastUpdateDate = "2026-01-01T00:00:00.000Z"
        try BuildDataCache(directory: directory).write(
            .compStats, data: old.encoded(), etag: nil, fetchedAt: now.addingTimeInterval(-86_400)
        )
        let source = StubSource([.compStats: .failure(BuildDataError.httpStatus(403))])
        let loaded = await store(source).load(now: now, bundledStats: FirestoneCompStats.bundled(), bundledStrategies: nil)
        #expect(loaded.statsOrigin == .bundled(reason: "Firestone answered HTTP 403 (no such file)"))
        #expect(loaded.stats?.timePeriod == "last-patch")
    }

    @Test("A body that isn't the file (a CDN error page) is never cached")
    func rejectsGarbage() async {
        let source = StubSource([
            .compStats: .success(.data(Data("<html>oops</html>".utf8), etag: "x")),
            .strategies: .success(.data(Data("<html>oops</html>".utf8), etag: "y")),
        ])
        let loaded = await store(source).load(now: now, bundledStats: nil, bundledStrategies: nil)
        #expect(loaded.stats == nil && loaded.strategies == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "comp-stats.json").path(percentEncoded: false)))
    }

    @Test("Firestone's URLs use the real time-window slugs")
    func urls() {
        #expect(FirestoneBuildDataSource().url(.compStats).absoluteString
            == "https://static.zerotoheroes.com/api/bgs/comp-stats/last-patch/overview-from-hourly.gz.json")
        #expect(FirestoneBuildDataSource(timePeriod: "past-three").url(.compStats).absoluteString
            == "https://static.zerotoheroes.com/api/bgs/comp-stats/past-three/overview-from-hourly.gz.json")
        #expect(FirestoneBuildDataSource().url(.strategies).absoluteString
            == "https://static.zerotoheroes.com/hearthstone/data/battlegrounds-strategies/bgs-comps-strategies.gz.json")
    }
}
