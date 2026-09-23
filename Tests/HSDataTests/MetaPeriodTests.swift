import Foundation
import HSData
import Testing

/// HSReplay's live meta period: fetched at most every 6 hours, cached by period, and
/// falling back to the last good copy and then the bundled one. Runs against a temporary
/// cache directory and a stubbed source (no network).
@Suite("Meta period")
final class MetaPeriodTests {
    final class StubSource: MetaPeriodSource, @unchecked Sendable {
        private let lock = NSLock()
        private var _requests = 0
        private var response: Result<Data, any Error>

        init(_ response: Result<Data, any Error>) { self.response = response }

        var requests: Int { lock.withLock { _requests } }
        func respond(_ response: Result<Data, any Error>) { lock.withLock { self.response = response } }

        func liveMetaPeriodJSON() async throws -> Data {
            try lock.withLock {
                _requests += 1
                return try response.get()
            }
        }
    }

    let directory: URL
    let now = Date(timeIntervalSince1970: 1_790_140_000)  // 2026-09-23 05:06Z

    init() {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "TavernLensMetaPeriodTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    static func period(_ name: String, start: TimeInterval) throws -> Data {
        let period = MetaPeriod(
            periodStart: Date(timeIntervalSince1970: start), name: name, minionTypes: [20, 24, 126],
            tagOverrides: [.init(dbfID: 1, tag: 1456, value: 0)]
        )
        return try JSONEncoder().encode(period)
    }

    func store(_ source: StubSource) -> MetaPeriodStore {
        MetaPeriodStore(cache: MetaPeriodCache(directory: directory), source: source)
    }

    @Test("Fetched once, then served from the cache for 6 hours, then fetched again")
    func refreshInterval() async throws {
        let source = StubSource(.success(try Self.period("P1", start: 1_790_000_000)))
        let store = store(source)
        let first = try #require(await store.load(now: now, bundled: nil))
        #expect(first.origin == .downloaded)
        #expect(first.period.name == "P1")
        #expect(first.period.override(dbfID: 1, tag: 1456) == 0)

        let cached = try #require(await store.load(now: now.addingTimeInterval(5 * 3600), bundled: nil))
        #expect(cached.origin == .cache)
        #expect(source.requests == 1)

        source.respond(.success(try Self.period("P2", start: 1_790_100_000)))
        let refreshed = try #require(await store.load(now: now.addingTimeInterval(6 * 3600 + 1), bundled: nil))
        #expect(refreshed.origin == .downloaded)
        #expect(refreshed.period.name == "P2")
        #expect(source.requests == 2)
    }

    @Test("Offline or refused: the last good copy, marked stale; with nothing cached, the bundled copy")
    func fallbacks() async throws {
        let source = StubSource(.success(try Self.period("P1", start: 1_790_000_000)))
        let store = store(source)
        _ = await store.load(now: now, bundled: nil)

        source.respond(.failure(MetaPeriodError.httpStatus(403)))
        let stale = try #require(await store.load(now: now.addingTimeInterval(7 * 3600), bundled: nil))
        #expect(stale.period.name == "P1")
        #expect(stale.isStale)
        guard case .stale(let reason) = stale.origin else { Issue.record("not stale: \(stale.origin)"); return }
        #expect(reason.contains("403"))

        // A bundled copy newer than the cached one wins.
        let bundled = MetaPeriod(periodStart: Date(timeIntervalSince1970: 1_790_050_000), name: "Bundled", minionTypes: [20])
        #expect(await store.load(now: now.addingTimeInterval(7 * 3600), bundled: bundled)?.period.name == "Bundled")

        let empty = MetaPeriodStore(
            cache: MetaPeriodCache(directory: directory.appending(path: "none")),
            source: StubSource(.failure(URLError(.notConnectedToInternet)))
        )
        let shipped = try #require(await empty.load(now: now))
        #expect(shipped.period.name == "Real 36.6.1")
        #expect(shipped.fetchedAt == nil)
        guard case .bundled = shipped.origin else { Issue.record("not bundled: \(shipped.origin)"); return }
        #expect(await empty.load(now: now, bundled: nil) == nil)
    }

    @Test("A malformed response is not cached and falls back")
    func malformed() async throws {
        let source = StubSource(.success(Data("<!DOCTYPE html><title>Just a moment...</title>".utf8)))
        let loaded = try #require(await store(source).load(now: now))
        guard case .bundled = loaded.origin else { Issue.record("not bundled: \(loaded.origin)"); return }
        #expect(MetaPeriodCache(directory: directory).latest() == nil)
    }

    @Test("The cache keeps the newest periods only")
    func retention() throws {
        let cache = MetaPeriodCache(directory: directory, limit: 2)
        for (i, start) in [1_790_000_000.0, 1_790_100_000, 1_790_200_000].enumerated() {
            let data = try Self.period("P\(i)", start: start)
            try cache.write(data, period: MetaPeriod(json: data), fetchedAt: now)
        }
        #expect(cache.latest()?.period.name == "P2")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        #expect(files.sorted() == ["1790100000000.json", "1790200000000.json"])
    }
}
