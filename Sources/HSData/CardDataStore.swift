import Foundation

/// Where card data is downloaded from.
public protocol CardDataSource: Sendable {
    /// The raw `cards.json` for `build`, or for the latest published build when nil.
    func cardsJSON(build: Int?) async throws -> Data
}

public enum CardDataError: Error, Equatable, CustomStringConvertible {
    /// HearthstoneJSON has no data for this build (yet); it usually follows a patch within a day.
    case notPublished(build: Int)
    case httpStatus(Int)
    /// Nothing cached and nothing downloadable.
    case unavailable

    public var description: String {
        switch self {
        case .notPublished(let build): "HearthstoneJSON has no card data for build \(build) yet"
        case .httpStatus(let status): "HearthstoneJSON answered HTTP \(status)"
        case .unavailable: "No card data cached and none could be downloaded"
        }
    }
}

/// HearthstoneJSON's build-pinned card data: `https://api.hearthstonejson.com/v1/<build>/<locale>/cards.json`.
public struct HearthstoneJSONSource: CardDataSource {
    public var locale: String
    public var baseURL: URL

    public init(locale: String = "enUS", baseURL: URL = URL(string: "https://api.hearthstonejson.com/v1/")!) {
        self.locale = locale
        self.baseURL = baseURL
    }

    public func url(build: Int?) -> URL {
        baseURL.appending(path: "\(build.map(String.init) ?? "latest")/\(locale)/cards.json")
    }

    public func cardsJSON(build: Int?) async throws -> Data {
        var request = URLRequest(url: url(build: build))
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        switch (status, build) {
        case (200, _): return data
        case (404, let build?): throw CardDataError.notPublished(build: build)
        default: throw CardDataError.httpStatus(status)
        }
    }
}

/// The on-disk card data cache: one folder per build, holding that build's `cards.json`.
///
/// It keeps at most `limit` builds: the current build plus the most recent others
/// (with the default limit of 3, the current build and the two before it).
public struct CardDataCache: Sendable {
    public let directory: URL
    public let limit: Int

    public init(directory: URL = CardDataCache.defaultDirectory, limit: Int = 3) {
        self.directory = directory
        self.limit = max(1, limit)
    }

    /// `~/Library/Application Support/TavernLens/CardData`.
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "TavernLens/CardData", directoryHint: .isDirectory)
    }

    static let fileName = "cards.json"

    func fileURL(build: Int) -> URL {
        directory.appending(path: "\(build)/\(Self.fileName)")
    }

    /// Builds with cached data, newest first.
    public var builds: [Int] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        return names.compactMap(Int.init)
            .filter { FileManager.default.fileExists(atPath: fileURL(build: $0).path(percentEncoded: false)) }
            .sorted(by: >)
    }

    func read(build: Int) -> Data? {
        try? Data(contentsOf: fileURL(build: build))
    }

    func write(_ data: Data, build: Int) throws {
        let folder = directory.appending(path: String(build), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: fileURL(build: build), options: .atomic)
    }

    func remove(build: Int) {
        try? FileManager.default.removeItem(at: directory.appending(path: String(build), directoryHint: .isDirectory))
    }

    /// Deletes every build beyond the limit, never `current`. Returns the builds removed.
    @discardableResult
    public func prune(keeping current: Int?) -> [Int] {
        var kept = current.map { [$0] } ?? []
        var removed: [Int] = []
        for build in builds where build != current {
            if kept.count < limit {
                kept.append(build)
            } else {
                remove(build: build)
                removed.append(build)
            }
        }
        return removed
    }
}

/// Card data as loaded, and where it came from.
public struct LoadedCardData: Sendable {
    public enum Origin: Hashable, Sendable {
        /// The requested build, from the cache (works offline).
        case cache
        /// The requested build, downloaded now and cached.
        case downloaded
        /// Not the requested build: the newest cached build, or HearthstoneJSON's latest,
        /// because the requested one couldn't be had. `db.build` says which build it is.
        case fallback(reason: String)
    }

    public var db: CardDB
    public var requestedBuild: Int?
    public var origin: Origin

    /// Whether the data is for the requested build.
    public var isExact: Bool {
        if case .fallback = origin { return false }
        return true
    }

    /// Whether Hearthstone running `build` needs other card data than this: it's a different
    /// build from the one loaded (a patch landed, or it was a fallback). Unknown builds don't.
    public func needsReload(forRunning build: Int?) -> Bool {
        guard let build else { return false }
        return db.build != build
    }
}

/// Loads the card data for the running build: from the cache when present, otherwise
/// downloaded once and cached, falling back to older cached data when offline.
public struct CardDataStore: Sendable {
    public let cache: CardDataCache
    public let source: any CardDataSource

    public init(cache: CardDataCache = CardDataCache(), source: any CardDataSource = HearthstoneJSONSource()) {
        self.cache = cache
        self.source = source
    }

    /// - Parameter build: the running Hearthstone build (see `HearthstoneBuild.installed()`),
    ///   or nil when unknown.
    public func load(build: Int?) async throws -> LoadedCardData {
        var failure: (any Error)?
        if let build {
            if let data = cache.read(build: build) {
                if let db = try? CardDB(build: build, json: data) {
                    cache.prune(keeping: build)
                    return LoadedCardData(db: db, requestedBuild: build, origin: .cache)
                }
                cache.remove(build: build)  // Unreadable; download it again.
            }
            do {
                let data = try await source.cardsJSON(build: build)
                let db = try CardDB(build: build, json: data)
                try cache.write(data, build: build)
                cache.prune(keeping: build)
                return LoadedCardData(db: db, requestedBuild: build, origin: .downloaded)
            } catch {
                failure = error
            }
        }

        let reason = failure.map { "\($0)" } ?? "Hearthstone build unknown"
        for cached in cache.builds {
            if let data = cache.read(build: cached), let db = try? CardDB(build: cached, json: data) {
                return LoadedCardData(db: db, requestedBuild: build, origin: .fallback(reason: reason))
            }
        }
        // Nothing cached: the latest data is closer than nothing. Not cached, since its build isn't known.
        do {
            let db = try CardDB(build: nil, json: await source.cardsJSON(build: nil))
            return LoadedCardData(db: db, requestedBuild: build, origin: .fallback(reason: reason))
        } catch {
            throw failure ?? error
        }
    }
}
