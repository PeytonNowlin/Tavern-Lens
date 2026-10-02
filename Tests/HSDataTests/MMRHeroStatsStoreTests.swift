import Foundation
import HSData
import Testing

@Suite("Rating-aware hero stats")
final class MMRHeroStatsStoreTests {
    struct Request: Hashable, Sendable { var window: HeroStatsWindow; var bucket: Int; var etag: String? }
    actor Source: HeroStatsSource, MMRPercentileSource {
        var bodies: [HeroStatsWindow: [Int: Result<HeroStatsResponse, any Error>]] = [:]
        var percentileAnswers: [HeroStatsWindow: Result<MMRPercentileResponse, any Error>] = [:]
        private(set) var requests: [Request] = []
        private(set) var percentileETags: [String?] = []

        func answer(_ window: HeroStatsWindow, _ bucket: Int, _ result: Result<HeroStatsResponse, any Error>) {
            bodies[window, default: [:]][bucket] = result
        }
        func answerPercentiles(_ window: HeroStatsWindow, _ result: Result<MMRPercentileResponse, any Error>) {
            percentileAnswers[window] = result
        }
        func fetch(window: HeroStatsWindow, mmrPercentile: Int, etag: String?) async throws -> HeroStatsResponse {
            requests.append(.init(window: window, bucket: mmrPercentile, etag: etag))
            guard let answer = bodies[window]?[mmrPercentile] else { throw HeroStatsFetchError.httpStatus(503) }
            return try answer.get()
        }
        func fetchPercentiles(window: HeroStatsWindow, etag: String?) async throws -> MMRPercentileResponse {
            percentileETags.append(etag)
            guard let answer = percentileAnswers[window] else { throw HeroStatsFetchError.httpStatus(503) }
            return try answer.get()
        }
    }

    let directory = FileManager.default.temporaryDirectory.appending(path: "TavernLensMMRTests-\(UUID().uuidString)")
    let now = MMRPercentileTests.now
    deinit { try? FileManager.default.removeItem(at: directory) }

    func store(_ source: Source, windows: [HeroStatsWindow] = [.pastThree]) -> HeroStatsStore {
        HeroStatsStore(cache: HeroStatsCache(directory: directory), source: source, windows: windows, percentileSource: source)
    }
    func body(_ average: Double = 4, rows: [MMRPercentileRow]? = MMRPercentileTests.rows, at date: Date? = nil) throws -> Data {
        try JSONEncoder().encode(FirestoneHeroStatsFile(lastUpdateDate: date ?? now, dataPoints: 60_000,
            heroStats: (0..<60).map { .init(heroCardId: "BG_H\($0)", dataPoints: 1000, averagePosition: average) },
            mmrPercentiles: rows))
    }
    func rating(_ value: Int = 6600, at date: Date? = nil) -> HeroStatsRating {
        .init(rating: value, source: .screen, recordedAt: date ?? now)
    }

    @Test("Fresh embedded evidence selects each window's own bucket and retains exact provenance")
    func sameWindowSelection() async throws {
        let source = Source()
        var different = MMRPercentileTests.rows
        different[2] = .init(percentile: 25, mmr: 6700)
        await source.answer(.pastThree, 100, .success(.body(try body(), etag: "all-three")))
        await source.answer(.pastThree, 25, .success(.body(try body(3.8), etag: "25-three")))
        await source.answer(.pastSeven, 100, .success(.body(try body(rows: different), etag: "all-seven")))
        await source.answer(.pastSeven, 50, .success(.body(try body(4.1, rows: different), etag: "50-seven")))
        let loaded = await store(source, windows: [.pastThree, .pastSeven]).load(rating: rating(), now: now)
        #expect(loaded.stats.bucket(of: .pastThree) == 25)
        #expect(loaded.stats.bucket(of: .pastSeven) == 50)
        #expect(loaded.stats.stat(for: "BG_H0")?.stat.averagePosition == 3.8)
        let evidence = try #require(loaded.stats.selections[.pastSeven])
        #expect(evidence.window == .pastSeven && evidence.mmrPercentile == 50 && evidence.matchedPercentile == 50)
        #expect(evidence.rating == rating())
        #expect(evidence.table?.sourceURL == FirestoneHeroStatsSource.url(window: .pastSeven, mmrPercentile: 100).absoluteString)
        #expect(evidence.table?.updatedAt == now)
        #expect(evidence.statsSourceURL == FirestoneHeroStatsSource.url(window: .pastSeven, mmrPercentile: 50).absoluteString)
        #expect(evidence.statsUpdatedAt == now)
        let percentileRequests = await source.percentileETags
        #expect(percentileRequests.isEmpty)
    }

    @Test("Raw top-one match deliberately uses a broader sample and records the reason")
    func topOneBroadens() async throws {
        let source = Source()
        await source.answer(.pastThree, 100, .success(.body(try body(), etag: nil)))
        await source.answer(.pastThree, 10, .success(.body(try body(3.7), etag: nil)))
        let loaded = await store(source).load(rating: rating(12_000), now: now)
        let evidence = try #require(loaded.stats.selections[.pastThree])
        #expect(evidence.matchedPercentile == 1 && evidence.mmrPercentile == 10)
        #expect(evidence.reason == .topOneBroadened)
        let requests = await source.requests
        #expect(requests.map(\.bucket) == [100, 10])
    }

    @Test("Missing, old, future or invalid ratings preserve the all-player path without requesting cutoffs")
    func noRecentRating() async throws {
        for reading in [nil, rating(at: now.addingTimeInterval(-24 * 3600 - 1)),
                        rating(at: now.addingTimeInterval(1)), rating(-1)] {
            let source = Source()
            await source.answer(.pastThree, 100, .success(.body(try body(), etag: nil)))
            let loaded = await store(source).load(rating: reading, now: now)
            #expect(loaded.stats.mmrPercentile == 100)
            #expect(loaded.stats.selections[.pastThree]?.reason == .noRecentRating)
            let requests = await source.requests
            let percentileRequests = await source.percentileETags
            #expect(requests.map(\.bucket) == [100] && percentileRequests.isEmpty)
        }
    }

    @Test("A standalone table is only needed for missing embedded evidence; 304 never renews its publication date")
    func standaloneAnd304() async throws {
        let source = Source()
        let bytes = try JSONEncoder().encode(MMRPercentileTests.rows)
        await source.answer(.pastThree, 100, .success(.body(try body(rows: nil), etag: "all")))
        await source.answer(.pastThree, 25, .success(.body(try body(3.8, rows: nil), etag: "25")))
        await source.answerPercentiles(.pastThree, .success(.body(bytes, etag: "cutoffs", lastModified: now)))
        let first = await store(source).load(rating: rating(), now: now)
        #expect(first.stats.mmrPercentile == 25)
        #expect(first.stats.selections[.pastThree]?.table?.sourceURL == FirestoneHeroStatsSource.percentilesURL(window: .pastThree).absoluteString)
        await source.answer(.pastThree, 100, .success(.notModified))
        await source.answer(.pastThree, 25, .success(.notModified))
        await source.answerPercentiles(.pastThree, .success(.notModified))
        let later = now.addingTimeInterval(25 * 3600)
        let stale = await store(source).load(rating: rating(at: later), now: later)
        #expect(stale.stats.mmrPercentile == 100)
        #expect(stale.stats.selections[.pastThree]?.reason == .noFreshTable)
        let sent = await source.percentileETags
        #expect(sent == [nil, "cutoffs"])
    }

    @Test("A response without a real publication timestamp cannot select a bucket")
    func missingPublicationDate() async throws {
        let source = Source()
        await source.answer(.pastThree, 100, .success(.body(try body(rows: nil), etag: nil)))
        await source.answerPercentiles(.pastThree, .success(.body(try JSONEncoder().encode(MMRPercentileTests.rows), etag: nil, lastModified: nil)))
        let loaded = await store(source).load(rating: rating(), now: now)
        #expect(loaded.stats.mmrPercentile == 100)
        #expect(loaded.stats.selections[.pastThree]?.reason == .noFreshTable)
    }

    @Test("Bucket caches and ETags stay separate; offline refresh retains the matching cached bucket")
    func bucketCacheFallback() async throws {
        let source = Source()
        await source.answer(.pastThree, 100, .success(.body(try body(), etag: "all")))
        await source.answer(.pastThree, 25, .success(.body(try body(3.8), etag: "25")))
        _ = await store(source).load(rating: rating(), now: now)
        await source.answer(.pastThree, 100, .failure(HeroStatsFetchError.httpStatus(503)))
        await source.answer(.pastThree, 25, .failure(HeroStatsFetchError.httpStatus(503)))
        let offline = await store(source).load(rating: rating(), now: now.addingTimeInterval(3600))
        #expect(offline.stats.bucket(of: .pastThree) == 25)
        #expect(offline.stats.stat(for: "BG_H0")?.stat.averagePosition == 3.8)
        #expect(offline.hadFailures)
        #expect(store(source).cached(rating: rating(), now: now).bucket(of: .pastThree) == 25)
        #expect(store(source).cached(rating: nil, now: now).bucket(of: .pastThree) == 100)
        let requests = await source.requests
        #expect(requests.map(\.etag) == [nil, nil, "all", "25"])
    }

    @Test("An unavailable selected bucket uses all-player evidence with explicit provenance")
    func missingSelectedBucket() async throws {
        let source = Source()
        await source.answer(.pastThree, 100, .success(.body(try body(), etag: nil)))
        let loaded = await store(source).load(rating: rating(), now: now)
        let evidence = try #require(loaded.stats.selections[.pastThree])
        #expect(evidence.matchedPercentile == 25 && evidence.mmrPercentile == 100)
        #expect(evidence.reason == .bucketUnavailable)
        #expect(loaded.stats.stat(for: "BG_H0")?.stat.averagePosition == 4)
    }
}
