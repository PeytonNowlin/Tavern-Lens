import Foundation

/// The two Firestone files build definitions come from.
public enum BuildDataFile: String, CaseIterable, Hashable, Sendable {
    case compStats = "comp-stats"
    case strategies
}

/// A conditional download's result.
public enum BuildDataFetch: Hashable, Sendable {
    /// The server's copy is the one we have (HTTP 304 for our ETag).
    case notModified
    case data(Data, etag: String?)
}

/// Where the build data is downloaded from.
public protocol BuildDataSource: Sendable {
    /// Downloads a file, conditionally when an ETag of the copy we have is given.
    func fetch(_ file: BuildDataFile, etag: String?) async throws -> BuildDataFetch
}

public enum BuildDataError: Error, Equatable, CustomStringConvertible {
    case httpStatus(Int)

    public var description: String {
        switch self {
        // Firestone's S3 bucket answers 403 for any key it doesn't have.
        case .httpStatus(403): "Firestone answered HTTP 403 (no such file)"
        case .httpStatus(let status): "Firestone answered HTTP \(status)"
        }
    }
}

/// Firestone's public static files (personal, non-commercial use is allowed by its terms).
///
/// This is its own small fetcher, deliberately separate from the hero-stats one, so the two
/// data sets can change independently.
public struct FirestoneBuildDataSource: BuildDataSource {
    /// Time windows Firestone publishes: `last-patch`, `past-seven`, `past-three`, `all-time`
    /// (`past-7`/`past-3` don't exist, and the bucket answers 403 for them).
    public var timePeriod: String
    public var userAgent: String

    public init(timePeriod: String = "last-patch", userAgent: String = "TavernLens/0.1 (macOS)") {
        self.timePeriod = timePeriod
        self.userAgent = userAgent
    }

    public func url(_ file: BuildDataFile) -> URL {
        switch file {
        case .compStats:
            URL(string: "https://static.zerotoheroes.com/api/bgs/comp-stats/\(timePeriod)/overview-from-hourly.gz.json")!
        case .strategies:
            URL(string: "https://static.zerotoheroes.com/hearthstone/data/battlegrounds-strategies/bgs-comps-strategies.gz.json")!
        }
    }

    public func fetch(_ file: BuildDataFile, etag: String?) async throws -> BuildDataFetch {
        var request = URLRequest(url: url(file))
        request.timeoutInterval = 60
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        // URLSession decompresses the gzip body (`content-encoding: gzip`) itself.
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        switch http?.statusCode ?? 200 {
        case 200: return .data(data, etag: http?.value(forHTTPHeaderField: "ETag"))
        case 304: return .notModified
        case let status: throw BuildDataError.httpStatus(status)
        }
    }
}

/// The last good build data on disk (`App Support/TavernLens/Builds`): the derived comp
/// stats and the raw strategies, each with its ETag. A file's modification date is when it
/// was last fetched or confirmed unchanged.
public struct BuildDataCache: Sendable {
    public let directory: URL

    public init(directory: URL = BuildDataCache.defaultDirectory) {
        self.directory = directory
    }

    /// `~/Library/Application Support/TavernLens/Builds`.
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "TavernLens/Builds", directoryHint: .isDirectory)
    }

    public struct Entry: Sendable {
        public var data: Data
        public var etag: String?
        public var fetchedAt: Date
    }

    private func url(_ file: BuildDataFile) -> URL { directory.appending(path: "\(file.rawValue).json") }
    private func etagURL(_ file: BuildDataFile) -> URL { directory.appending(path: "\(file.rawValue).etag") }

    public func read(_ file: BuildDataFile) -> Entry? {
        let url = url(file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let etag = (try? String(contentsOf: etagURL(file), encoding: .utf8)).flatMap { $0.isEmpty ? nil : $0 }
        return Entry(data: data, etag: etag, fetchedAt: date ?? .distantPast)
    }

    public func write(_ file: BuildDataFile, data: Data, etag: String?, fetchedAt: Date) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(file), options: .atomic)
        try (etag ?? "").write(to: etagURL(file), atomically: true, encoding: .utf8)
        touch(file, at: fetchedAt)
    }

    /// Marks the cached copy as confirmed current at `date`.
    public func touch(_ file: BuildDataFile, at date: Date) {
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url(file).path(percentEncoded: false))
    }
}

/// Build data as loaded, and where each part came from.
public struct LoadedBuildData: Hashable, Sendable {
    public enum Origin: Hashable, Sendable {
        /// Fetched now and cached.
        case downloaded
        /// The cached copy: fresh enough not to fetch, or confirmed unchanged (HTTP 304).
        case cache
        /// The fetch failed; the cached copy, however old.
        case stale(reason: String)
        /// The fetch failed and nothing usable is cached: the copy shipped with the app.
        case bundled(reason: String)

        public var isStale: Bool {
            switch self {
            case .downloaded, .cache: false
            case .stale, .bundled: true
            }
        }
    }

    public var stats: FirestoneCompStats?
    public var statsOrigin: Origin?
    public var strategies: FirestoneStrategies?
    public var strategiesOrigin: Origin?

    /// For `BuildCatalog.compose`.
    public func provenance(overridesPatch: String?) -> BuildCatalog.Provenance {
        BuildCatalog.Provenance(
            statsUpdated: stats?.lastUpdateDate, statsTimePeriod: stats?.timePeriod,
            statsIsStale: statsOrigin?.isStale ?? true, strategiesIsStale: strategiesOrigin?.isStale ?? true,
            overridesPatch: overridesPatch
        )
    }
}

/// Loads Firestone's comp stats and strategies: from the cache while fresh, otherwise
/// fetched (conditionally, with the cached ETag) and cached, falling back to the last good
/// copy and then to the copy shipped with the app.
public struct BuildDataStore: Sendable {
    /// Refresh at app start and every 6 hours (Firestone rebuilds about every 3 hours; its CDN
    /// caches for up to 8).
    public static let refreshInterval: TimeInterval = 6 * 60 * 60

    public let cache: BuildDataCache
    public let source: any BuildDataSource
    public let refreshInterval: TimeInterval

    public init(
        cache: BuildDataCache = BuildDataCache(), source: any BuildDataSource = FirestoneBuildDataSource(),
        refreshInterval: TimeInterval = BuildDataStore.refreshInterval
    ) {
        self.cache = cache
        self.source = source
        self.refreshInterval = refreshInterval
    }

    public func load(
        now: Date = Date(), bundledStats: FirestoneCompStats? = FirestoneCompStats.bundled(),
        bundledStrategies: FirestoneStrategies? = FirestoneStrategies.bundled()
    ) async -> LoadedBuildData {
        let stats = await load(
            .compStats, now: now, bundled: bundledStats,
            decodeCached: { try FirestoneCompStats(json: $0) },
            // The raw file is reduced before it's cached.
            decodeDownloaded: { raw in
                let stats = try FirestoneCompStats.derive(fromFirestone: raw)
                return (stats, try stats.encoded())
            },
            isNewer: { cached, bundled in (cached.updatedAt ?? .distantPast) >= (bundled.updatedAt ?? .distantPast) }
        )
        let strategies = await load(
            .strategies, now: now, bundled: bundledStrategies,
            decodeCached: { try FirestoneStrategies(json: $0) },
            decodeDownloaded: { raw in (try FirestoneStrategies(json: raw), raw) },
            isNewer: { _, _ in true }
        )
        return LoadedBuildData(
            stats: stats?.value, statsOrigin: stats?.origin, strategies: strategies?.value,
            strategiesOrigin: strategies?.origin
        )
    }

    private func load<Value: Sendable>(
        _ file: BuildDataFile, now: Date, bundled: Value?,
        decodeCached: (Data) throws -> Value,
        decodeDownloaded: (Data) throws -> (Value, Data),
        isNewer: (Value, Value) -> Bool
    ) async -> (value: Value, origin: LoadedBuildData.Origin)? {
        let entry = cache.read(file)
        let cached = entry.flatMap { entry in (try? decodeCached(entry.data)).map { (entry, $0) } }
        if let (entry, value) = cached, entry.fetchedAt <= now, now.timeIntervalSince(entry.fetchedAt) < refreshInterval {
            return (value, .cache)
        }
        let reason: String
        do {
            switch try await source.fetch(file, etag: cached?.0.etag) {
            case .notModified:
                if let (_, value) = cached {
                    cache.touch(file, at: now)
                    return (value, .cache)
                }
                reason = "HTTP 304 without a cached copy"
            case .data(let data, let etag):
                let (value, stored) = try decodeDownloaded(data)
                try? cache.write(file, data: stored, etag: etag, fetchedAt: now)
                return (value, .downloaded)
            }
        } catch {
            reason = "\(error)"
        }
        if let (_, value) = cached, bundled.map({ isNewer(value, $0) }) ?? true {
            return (value, .stale(reason: reason))
        }
        return bundled.map { ($0, .bundled(reason: reason)) }
    }
}
