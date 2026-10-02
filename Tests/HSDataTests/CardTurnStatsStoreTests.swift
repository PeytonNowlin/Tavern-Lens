import Foundation
import HSData
import Testing

@Suite("Card performance source and cache")
final class CardTurnStatsStoreTests {
    actor StubSource: CardTurnStatsSource {
        var response: Result<CardTurnStatsResponse, any Error>
        private(set) var requests: [String?] = []

        init(_ response: Result<CardTurnStatsResponse, any Error>) { self.response = response }
        func respond(_ response: Result<CardTurnStatsResponse, any Error>) { self.response = response }
        func fetch(etag: String?) async throws -> CardTurnStatsResponse {
            requests.append(etag)
            return try response.get()
        }
    }

    let directory = FileManager.default.temporaryDirectory
        .appending(path: "TavernLensCardTurnTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let now = CardTurnStatsTests.now

    deinit { try? FileManager.default.removeItem(at: directory) }

    func store(_ source: StubSource) -> CardTurnStatsStore {
        CardTurnStatsStore(cache: CardTurnStatsCache(directory: directory), source: source)
    }

    @Test("A downloaded snapshot is available offline and cached for six hours")
    func downloadAndCache() async throws {
        let source = StubSource(.success(.data(CardTurnStatsTests.raw, etag: "\"v1\"")))
        let first = await store(source).load(now: now)
        #expect(first.origin == .downloaded)
        #expect(first.stats?.entry(cardID: "BG_TEST", turn: 8, now: now)?.impact == -0.75)
        #expect(store(source).cached() == first.stats)
        await source.respond(.failure(CardTurnStatsError.httpStatus(503)))
        let cached = await store(source).load(now: now.addingTimeInterval(5 * 3600))
        #expect(cached.origin == .cache)
        #expect(cached.stats == first.stats)
        let requests = await source.requests
        #expect(requests == [nil])
    }

    @Test("Conditional 304 preserves source evidence and restarts only the download clock")
    func notModified() async throws {
        let source = StubSource(.success(.data(CardTurnStatsTests.raw, etag: "\"v1\"")))
        let first = await store(source).load(now: now)
        await source.respond(.success(.notModified))
        let later = now.addingTimeInterval(7 * 3600)
        let checked = await store(source).load(now: later)
        #expect(checked.origin == .notModified)
        #expect(checked.stats == first.stats)
        #expect(checked.checkedAt == later)
        let again = await store(source).load(now: later.addingTimeInterval(5 * 3600))
        #expect(again.origin == .cache)
        let requests = await source.requests
        #expect(requests == [nil, "\"v1\""])
    }

    @Test("Incomplete comparator rows do not discard complete evidence on download or cache reload")
    func incompleteComparison() async {
        let source = StubSource(.success(.data(CardTurnStatsTests.incompleteRaw, etag: "\"v1\"")))
        let loaded = await store(source).load(now: now)
        #expect(loaded.origin == .downloaded)
        #expect(loaded.stats?.entry(cardID: "BG_TEST", turn: 8, now: now)?.impact == -0.75)
        #expect(loaded.stats?.entry(cardID: "BG_TEST", turn: 9, now: now) == nil)
        #expect(store(source).cached() == loaded.stats)
        let cached = await store(source).load(now: now.addingTimeInterval(3600))
        #expect(cached.origin == .cache)
        #expect(cached.stats == loaded.stats)
    }

    @Test("Failures have no bundled substitute and preserve the last good cache")
    func failedSource() async throws {
        let source = StubSource(.failure(CardTurnStatsError.httpStatus(503)))
        let empty = await store(source).load(now: now)
        #expect(empty.stats == nil)
        #expect(empty.hadFailures)
        if case .missing = empty.origin {} else { Issue.record("An empty cache should report missing data") }
        await source.respond(.success(.data(CardTurnStatsTests.raw, etag: "\"good\"")))
        let good = await store(source).load(now: now)
        await source.respond(.failure(CardTurnStatsError.httpStatus(503)))
        let fallback = await store(source).load(now: now.addingTimeInterval(7 * 3600))
        #expect(fallback.stats == good.stats)
        #expect(fallback.hadFailures)
        if case .stale = fallback.origin {} else { Issue.record("A failed refresh should report its cached fallback") }
        #expect(store(source).cached() == good.stats)
    }

    @Test("Bad payloads never replace good evidence or its conditional token")
    func rejectsBadRefreshes() async throws {
        let source = StubSource(.success(.data(CardTurnStatsTests.raw, etag: "\"good\"")))
        let good = await store(source).load(now: now)
        let raw = String(decoding: CardTurnStatsTests.raw, as: UTF8.self)
        let invalidBodies = [
            Data("<html>CDN error</html>".utf8),
            Data(raw.replacingOccurrences(of: "2026-10-02T12:00:00.000Z", with: "2026-09-01T12:00:00Z").utf8),
            Data(raw.replacingOccurrences(of: "2026-10-02T12:00:00.000Z", with: "2026-10-03T12:00:00Z").utf8),
            Data(raw.replacingOccurrences(of: "last-patch", with: "all-time").utf8),
            Data(raw.replacingOccurrences(of: "\"totalOther\":600", with: "\"totalOther\":199").utf8),
            Data(repeating: 32, count: CardTurnStatsStore.maximumResponseBytes + 1),
        ]
        for body in invalidBodies {
            await source.respond(.success(.data(body, etag: "\"bad\"")))
            let fallback = await store(source).load(now: now.addingTimeInterval(7 * 3600))
            #expect(fallback.hadFailures)
            #expect(fallback.stats == good.stats)
            #expect(store(source).cached() == good.stats)
        }
        await source.respond(.success(.notModified))
        let confirmed = await store(source).load(now: now.addingTimeInterval(7 * 3600))
        #expect(confirmed.origin == .notModified)
        let requests = await source.requests
        #expect(requests.dropFirst().allSatisfy { $0 == "\"good\"" })
    }

    @Test("A 304 without cached data is missing evidence")
    func missingCacheFor304() async {
        let source = StubSource(.success(.notModified))
        let loaded = await store(source).load(now: now)
        #expect(loaded.stats == nil)
        #expect(loaded.hadFailures)
        #expect(store(source).cached() == nil)
    }

    @Test("Confirmed retrieval cannot rejuvenate a source older than 48 hours")
    func expiredSource() async throws {
        let source = StubSource(.success(.data(CardTurnStatsTests.raw, etag: "\"good\"")))
        let good = await store(source).load(now: now)
        await source.respond(.success(.notModified))
        let later = now.addingTimeInterval(49 * 3600)
        let expired = await store(source).load(now: later)
        #expect(expired.hadFailures)
        #expect(expired.stats == good.stats)
        #expect(expired.stats?.entry(cardID: "BG_TEST", turn: 8, now: later) == nil)
    }
}
