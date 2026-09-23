import Foundation

/// An answer to a conditional GET.
public enum HeroStatsResponse: Hashable, Sendable {
    /// The server's copy is the one we have (`304 Not Modified` for our `If-None-Match`).
    case notModified
    case body(Data, etag: String?)
}

public enum HeroStatsFetchError: Error, Equatable, CustomStringConvertible {
    case httpStatus(Int)
    /// The file decoded but looked empty or partial (under 50 heroes, or no games).
    case unusable
    case undecodable(String)

    public var description: String {
        switch self {
        // S3 answers 403 for a key that doesn't exist (research §2.1).
        case .httpStatus(403): "Firestone answered HTTP 403 (no such stats file)"
        case .httpStatus(let status): "Firestone answered HTTP \(status)"
        case .unusable: "the stats file was empty or partial"
        case .undecodable(let reason): "the stats file didn't decode: \(reason)"
        }
    }
}

/// Where hero-stats files are downloaded from.
public protocol HeroStatsSource: Sendable {
    /// Fetches `window` for MMR bucket `mmrPercentile`, conditionally on `etag` when given.
    func fetch(window: HeroStatsWindow, mmrPercentile: Int, etag: String?) async throws -> HeroStatsResponse
}

/// Firestone's public static stats files (docs/research/hero-pick-stats.md §2). No auth; the
/// CDN serves gzip, which URLSession decompresses, and honours `If-None-Match`.
public struct FirestoneHeroStatsSource: HeroStatsSource {
    public static let base = URL(string: "https://static.zerotoheroes.com/api/bgs/hero-stats/")!

    public var userAgent: String

    public init(userAgent: String = "TavernLens/0.1 (macOS)") {
        self.userAgent = userAgent
    }

    /// `…/hero-stats/mmr-100/past-three/overview-from-hourly.gz.json`.
    public static func url(window: HeroStatsWindow, mmrPercentile: Int) -> URL {
        base.appending(path: "mmr-\(mmrPercentile)/\(window.rawValue)/overview-from-hourly.gz.json")
    }

    public func fetch(window: HeroStatsWindow, mmrPercentile: Int, etag: String?) async throws -> HeroStatsResponse {
        var request = URLRequest(url: Self.url(window: window, mmrPercentile: mmrPercentile))
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        switch http?.statusCode ?? 200 {
        case 200: return .body(data, etag: http?.value(forHTTPHeaderField: "ETag"))
        case 304: return .notModified
        case let status: throw HeroStatsFetchError.httpStatus(status)
        }
    }
}

/// The last good copy of each stats file on disk: `<bucket>/<window>.json` plus
/// `<window>.etag`. The JSON's modification date is when it was last fetched or confirmed
/// unchanged.
public struct HeroStatsCache: Sendable {
    public let directory: URL

    public init(directory: URL = HeroStatsCache.defaultDirectory) {
        self.directory = directory
    }

    /// `~/Library/Application Support/TavernLens/HeroStats`.
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "TavernLens/HeroStats", directoryHint: .isDirectory)
    }

    public struct Entry: Sendable {
        public var file: FirestoneHeroStatsFile
        public var etag: String?
        public var fetchedAt: Date
    }

    public func read(_ window: HeroStatsWindow, mmrPercentile: Int) -> Entry? {
        let url = jsonURL(window, mmrPercentile)
        guard let data = try? Data(contentsOf: url), let file = try? FirestoneHeroStatsFile(json: data) else {
            return nil
        }
        let etag = try? String(contentsOf: etagURL(window, mmrPercentile), encoding: .utf8)
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return Entry(file: file, etag: etag?.isEmpty == false ? etag : nil, fetchedAt: date ?? .distantPast)
    }

    public func write(_ data: Data, etag: String?, window: HeroStatsWindow, mmrPercentile: Int, fetchedAt: Date) throws {
        let json = jsonURL(window, mmrPercentile)
        try FileManager.default.createDirectory(at: json.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: json, options: .atomic)
        try (etag ?? "").write(to: etagURL(window, mmrPercentile), atomically: true, encoding: .utf8)
        try touch(window, mmrPercentile: mmrPercentile, at: fetchedAt)
    }

    /// Marks the cached copy as confirmed current at `date` (a 304).
    public func touch(_ window: HeroStatsWindow, mmrPercentile: Int, at date: Date) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: date], ofItemAtPath: jsonURL(window, mmrPercentile).path(percentEncoded: false)
        )
    }

    private func jsonURL(_ window: HeroStatsWindow, _ bucket: Int) -> URL {
        directory.appending(path: "mmr-\(bucket)/\(window.rawValue).json")
    }

    private func etagURL(_ window: HeroStatsWindow, _ bucket: Int) -> URL {
        directory.appending(path: "mmr-\(bucket)/\(window.rawValue).etag")
    }
}

/// What a load found, per window.
public struct LoadedHeroStats: Sendable {
    public enum Origin: Hashable, Sendable {
        /// Downloaded now and cached.
        case downloaded
        /// The server confirmed the cached copy is current (304).
        case notModified
        /// The fetch failed; the last good cached copy.
        case stale(reason: String)
        /// The fetch failed and nothing is cached.
        case missing(reason: String)
    }

    /// Every window that has a file (downloaded or cached).
    public var stats: HeroStatsSet
    public var origins: [HeroStatsWindow: Origin]

    /// Some window couldn't be refreshed.
    public var hadFailures: Bool {
        origins.values.contains {
            switch $0 {
            case .downloaded, .notModified: false
            case .stale, .missing: true
            }
        }
    }
}

/// Loads Firestone's hero stats (all players by default) for the three windows the hero pick
/// uses. Each window is fetched with the cached copy's ETag, so an unchanged file costs a
/// 304; a failed fetch, or a file that looks empty or partial, keeps the last good copy.
/// The app calls `load` at launch and every `refreshInterval`.
public struct HeroStatsStore: Sendable {
    /// Firestone rebuilds the files about every 3 h and its CDN caches them for 8 h.
    public static let refreshInterval: TimeInterval = 6 * 60 * 60

    public let cache: HeroStatsCache
    public let source: any HeroStatsSource
    public let mmrPercentile: Int
    public let windows: [HeroStatsWindow]

    public init(
        cache: HeroStatsCache = HeroStatsCache(), source: any HeroStatsSource = FirestoneHeroStatsSource(),
        mmrPercentile: Int = 100, windows: [HeroStatsWindow] = HeroStatsWindow.preference
    ) {
        self.cache = cache
        self.source = source
        self.mmrPercentile = mmrPercentile
        self.windows = windows
    }

    public func load(now: Date = Date()) async -> LoadedHeroStats {
        var files: [HeroStatsWindow: FirestoneHeroStatsFile] = [:]
        var origins: [HeroStatsWindow: LoadedHeroStats.Origin] = [:]
        for window in windows {
            let cached = cache.read(window, mmrPercentile: mmrPercentile)
            do {
                switch try await source.fetch(window: window, mmrPercentile: mmrPercentile, etag: cached?.etag) {
                case .notModified:
                    guard let cached else { throw HeroStatsFetchError.httpStatus(304) }
                    try? cache.touch(window, mmrPercentile: mmrPercentile, at: now)
                    files[window] = cached.file
                    origins[window] = .notModified
                case .body(let data, let etag):
                    let file: FirestoneHeroStatsFile
                    do { file = try FirestoneHeroStatsFile(json: data) } catch {
                        throw HeroStatsFetchError.undecodable("\(error)")
                    }
                    guard file.isUsable else { throw HeroStatsFetchError.unusable }
                    try? cache.write(data, etag: etag, window: window, mmrPercentile: mmrPercentile, fetchedAt: now)
                    files[window] = file
                    origins[window] = .downloaded
                }
            } catch {
                if let cached {
                    files[window] = cached.file
                    origins[window] = .stale(reason: "\(error)")
                } else {
                    origins[window] = .missing(reason: "\(error)")
                }
            }
        }
        return LoadedHeroStats(stats: HeroStatsSet(mmrPercentile: mmrPercentile, files: files), origins: origins)
    }

    /// The cached copies only, without touching the network (for a first draw at launch).
    public func cached() -> HeroStatsSet {
        var files: [HeroStatsWindow: FirestoneHeroStatsFile] = [:]
        for window in windows {
            if let entry = cache.read(window, mmrPercentile: mmrPercentile) { files[window] = entry.file }
        }
        return HeroStatsSet(mmrPercentile: mmrPercentile, files: files)
    }
}
