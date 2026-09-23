import Foundation
import HSData
import Testing

/// Card data pinned to the running build: download once, reuse offline, bounded cache.
/// Runs against a temporary cache directory and a stubbed source (no network).
@Suite("Card data")
final class CardDataTests {
    /// A trimmed, real HearthstoneJSON `cards.json` (build 251952).
    static let fixtureURL = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures/HearthstoneJSON/cards.251952.trimmed.json")

    static func fixture() throws -> Data { try Data(contentsOf: fixtureURL) }

    /// Serves the fixture for any build it's told it has, counting requests.
    final class StubSource: CardDataSource, @unchecked Sendable {
        private let lock = NSLock()
        private var published: Set<Int>
        private var online: Bool
        private var _requests: [Int?] = []
        let payload: Data

        init(published: Set<Int>, online: Bool = true, payload: Data) {
            self.published = published
            self.online = online
            self.payload = payload
        }

        var requests: [Int?] { lock.withLock { _requests } }
        func goOffline() { lock.withLock { online = false } }

        func cardsJSON(build: Int?) async throws -> Data {
            try lock.withLock {
                _requests.append(build)
                guard online else { throw URLError(.notConnectedToInternet) }
                if let build, !published.contains(build) { throw CardDataError.notPublished(build: build) }
                return payload
            }
        }
    }

    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "TavernLensCardDataTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func store(_ source: StubSource) -> CardDataStore {
        CardDataStore(cache: CardDataCache(directory: directory), source: source)
    }

    @Test("The trimmed fixture decodes and resolves card IDs, dbfIds, golden links and tribes")
    func cardDB() throws {
        let db = try CardDB(build: 251_952, json: Self.fixture())
        #expect(db.name(of: "TB_BaconShop_HERO_15") == "George the Fallen")
        #expect(db.name(of: "BG36_HERO_002") == "Kith'ix")
        #expect(db.name(of: "NOT_A_CARD") == nil)
        let geomancer = try #require(db["BG20_100"])
        #expect(geomancer.techLevel == 1)
        #expect(geomancer.cardType == .minion)
        #expect(geomancer.tribes == [.quilboar])
        #expect(geomancer.isBattlegroundsPoolMinion == true)
        let golden = try #require(geomancer.battlegroundsPremiumDbfId.flatMap(db.card(dbfID:)))
        #expect(golden.id == "BG20_100_G")
    }

    @Test("A build is downloaded once, then served from the cache, also offline")
    func downloadOnceThenOffline() async throws {
        let source = StubSource(published: [251_952], payload: try Self.fixture())
        let first = try await store(source).load(build: 251_952)
        #expect(first.origin == .downloaded)
        #expect(first.db.build == 251_952)
        #expect(first.db.name(of: "TB_BaconShop_HERO_15") == "George the Fallen")

        source.goOffline()
        let second = try await store(source).load(build: 251_952)
        #expect(second.origin == .cache)
        #expect(second.isExact)
        #expect(second.db.count == first.db.count)
        #expect(source.requests == [251_952])
    }

    @Test("The cache keeps at most the current build plus the two before it")
    func retention() async throws {
        let builds = [250_100, 250_200, 250_300, 250_400, 251_952]
        let source = StubSource(published: Set(builds), payload: try Self.fixture())
        for build in builds {
            _ = try await store(source).load(build: build)
            #expect(CardDataCache(directory: directory).builds.count <= 3)
        }
        #expect(CardDataCache(directory: directory).builds == [251_952, 250_400, 250_300])

        // Going back to a cached older build keeps it as current and doesn't download.
        let older = try await store(source).load(build: 250_300)
        #expect(older.origin == .cache)
        #expect(CardDataCache(directory: directory).builds == [251_952, 250_400, 250_300])
        #expect(source.requests.count == builds.count)
    }

    @Test("Offline with a new build: the newest cached build is used and marked stale")
    func offlineFallback() async throws {
        let source = StubSource(published: [250_100, 250_200], payload: try Self.fixture())
        _ = try await store(source).load(build: 250_100)
        _ = try await store(source).load(build: 250_200)

        source.goOffline()
        let loaded = try await store(source).load(build: 251_952)
        #expect(!loaded.isExact)
        #expect(loaded.requestedBuild == 251_952)
        #expect(loaded.db.build == 250_200)
        #expect(CardDataCache(directory: directory).builds == [250_200, 250_100])
    }

    @Test("A build HearthstoneJSON hasn't published yet falls back to cached data")
    func notPublishedYet() async throws {
        let source = StubSource(published: [250_100], payload: try Self.fixture())
        _ = try await store(source).load(build: 250_100)
        let loaded = try await store(source).load(build: 251_952)
        #expect(!loaded.isExact)
        #expect(loaded.db.build == 250_100)
    }

    @Test("Nothing cached and nothing published for the build: the latest data, not cached")
    func latestWhenNothingCached() async throws {
        let source = StubSource(published: [], payload: try Self.fixture())
        let loaded = try await store(source).load(build: 251_952)
        #expect(!loaded.isExact)
        #expect(loaded.db.build == nil)
        #expect(source.requests == [251_952, nil])
        #expect(CardDataCache(directory: directory).builds.isEmpty)
    }

    @Test("Nothing cached and offline: loading fails")
    func offlineWithoutCache() async throws {
        let source = StubSource(published: [251_952], online: false, payload: try Self.fixture())
        await #expect(throws: (any Error).self) { try await store(source).load(build: 251_952) }
    }

    @Test("An unreadable cached file is downloaded again")
    func corruptCache() async throws {
        let source = StubSource(published: [251_952], payload: try Self.fixture())
        _ = try await store(source).load(build: 251_952)
        let file = directory.appending(path: "251952/cards.json")
        try Data("not json".utf8).write(to: file)

        let loaded = try await store(source).load(build: 251_952)
        #expect(loaded.origin == .downloaded)
        #expect(try Data(contentsOf: file) == Self.fixture())
    }

    @Test("Card data is requested from HearthstoneJSON pinned to the build")
    func sourceURL() {
        let source = HearthstoneJSONSource()
        #expect(source.url(build: 251_952).absoluteString == "https://api.hearthstonejson.com/v1/251952/enUS/cards.json")
        #expect(source.url(build: nil).absoluteString == "https://api.hearthstonejson.com/v1/latest/enUS/cards.json")
    }

    @Test("The running build is read from the Hearthstone app's bundle version")
    func installedBuild() throws {
        let app = directory.appending(path: "Hearthstone.app", directoryHint: .isDirectory)
        #expect(HearthstoneBuild.installed(appURL: app) == nil)

        let contents = app.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleVersion": "36.6.251952", "CFBundleShortVersionString": "1.0"],
            format: .xml, options: 0
        )
        try plist.write(to: contents.appending(path: "Info.plist"))
        #expect(HearthstoneBuild.installed(appURL: app) == 251_952)

        #expect(HearthstoneBuild.parse(bundleVersion: "1.0") == nil)
        #expect(HearthstoneBuild.parse(bundleVersion: "garbage") == nil)
    }
}
