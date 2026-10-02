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
public struct FirestoneHeroStatsSource: HeroStatsSource, MMRPercentileSource {
    public static let base = URL(string: "https://static.zerotoheroes.com/api/bgs/hero-stats/")!

    public var userAgent: String

    public init(userAgent: String = "TavernLens/0.1 (macOS)") {
        self.userAgent = userAgent
    }

    /// `…/hero-stats/mmr-100/past-three/overview-from-hourly.gz.json`.
    public static func url(window: HeroStatsWindow, mmrPercentile: Int) -> URL {
        base.appending(path: "mmr-\(mmrPercentile)/\(window.rawValue)/overview-from-hourly.gz.json")
    }

    public static func percentilesURL(window: HeroStatsWindow) -> URL {
        base.appending(path: "\(window.rawValue)/mmr-percentiles.gz.json")
    }

    public func fetchPercentiles(window: HeroStatsWindow, etag: String?) async throws -> MMRPercentileResponse {
        let url = Self.percentilesURL(window: window)
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.url == url else { throw HeroStatsFetchError.unusable }
        switch http.statusCode {
        case 200:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            let published = http.value(forHTTPHeaderField: "Last-Modified").flatMap(formatter.date(from:))
            return .body(data, etag: http.value(forHTTPHeaderField: "ETag"), lastModified: published)
        case 304: return .notModified
        default: throw HeroStatsFetchError.httpStatus(http.statusCode)
        }
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

    public struct PercentileEntry: Codable, Sendable {
        public var table: MMRPercentileTable
        public var etag: String?
    }

    public func readPercentiles(_ window: HeroStatsWindow) -> PercentileEntry? {
        guard let data = try? Data(contentsOf: percentileURL(window)),
              let entry = try? JSONDecoder().decode(PercentileEntry.self, from: data),
              entry.table.window == window,
              entry.table.sourceURL == FirestoneHeroStatsSource.percentilesURL(window: window).absoluteString
        else { return nil }
        return entry
    }

    public func writePercentiles(_ table: MMRPercentileTable, etag: String?) throws {
        let url = percentileURL(table.window)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(PercentileEntry(table: table, etag: etag)).write(to: url, options: .atomic)
    }

    private func percentileURL(_ window: HeroStatsWindow) -> URL {
        directory.appending(path: "percentiles/\(window.rawValue).json")
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
    public let percentileSource: any MMRPercentileSource

    public init(
        cache: HeroStatsCache = HeroStatsCache(), source: any HeroStatsSource = FirestoneHeroStatsSource(),
        mmrPercentile: Int = 100, windows: [HeroStatsWindow] = HeroStatsWindow.preference,
        percentileSource: any MMRPercentileSource = FirestoneHeroStatsSource()
    ) {
        self.cache = cache
        self.source = source
        self.mmrPercentile = mmrPercentile
        self.windows = windows
        self.percentileSource = percentileSource
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

    /// Uses a recent own-player rating. Every window keeps its own cutoffs and bucket cache.
    /// The all-player file supplies embedded cutoffs and a usable fallback when the selected file is missing.
    public func load(rating: HeroStatsRating?, now: Date = Date()) async -> LoadedHeroStats {
        var files: [HeroStatsWindow: FirestoneHeroStatsFile] = [:]
        var origins: [HeroStatsWindow: LoadedHeroStats.Origin] = [:]
        var selections: [HeroStatsWindow: HeroStatsMMRSelection] = [:]
        for window in windows {
            let allPlayers = await loadWindow(window, bucket: 100, now: now)
            var table: MMRPercentileTable?
            if rating?.isRecent(at: now) == true {
                table = embeddedTable(allPlayers.entry, window: window, now: now)
                if table == nil { table = await loadPercentiles(window, now: now) }
            }
            let match = match(rating: rating, table: table, now: now)
            var actualBucket = match.bucket
            var result = match.bucket == 100 ? allPlayers : await loadWindow(window, bucket: match.bucket, now: now)
            var reason = match.reason
            if result.entry == nil, match.bucket != 100 {
                actualBucket = 100
                reason = .bucketUnavailable
                let failure = result.origin
                result = allPlayers
                origins[window] = .stale(reason: "MMR bucket \(match.bucket) unavailable; using all players (\(failure))")
            } else {
                origins[window] = result.origin
            }
            if let entry = result.entry { files[window] = entry.file }
            selections[window] = selection(window, bucket: actualBucket, matched: match.matched, rating: rating,
                table: table, entry: result.entry, now: now, reason: reason)
        }
        return LoadedHeroStats(stats: selectedSet(files: files, selections: selections), origins: origins)
    }

    /// The same selection from local evidence only, for startup and rating changes.
    public func cached(rating: HeroStatsRating?, now: Date = Date()) -> HeroStatsSet {
        var files: [HeroStatsWindow: FirestoneHeroStatsFile] = [:]
        var selections: [HeroStatsWindow: HeroStatsMMRSelection] = [:]
        for window in windows {
            let allPlayers = usable(cache.read(window, mmrPercentile: 100))
            var table: MMRPercentileTable?
            if rating?.isRecent(at: now) == true {
                table = embeddedTable(allPlayers, window: window, now: now)
                if table == nil, let saved = cache.readPercentiles(window)?.table, saved.isFresh(at: now) { table = saved }
            }
            let match = match(rating: rating, table: table, now: now)
            let chosen = match.bucket == 100 ? allPlayers : usable(cache.read(window, mmrPercentile: match.bucket))
            let fallback = chosen == nil && match.bucket != 100
            let entry = fallback ? allPlayers : chosen
            if let entry { files[window] = entry.file }
            selections[window] = selection(window, bucket: fallback ? 100 : match.bucket, matched: match.matched,
                rating: rating, table: table, entry: entry, now: now, reason: fallback ? .bucketUnavailable : match.reason)
        }
        return selectedSet(files: files, selections: selections)
    }

    private func usable(_ entry: HeroStatsCache.Entry?) -> HeroStatsCache.Entry? {
        guard let entry, entry.file.isUsable else { return nil }
        return entry
    }

    private struct WindowResult {
        var entry: HeroStatsCache.Entry?
        var origin: LoadedHeroStats.Origin
    }

    /// Reuses the existing fixed-bucket loader without changing its callers or fallback behavior.
    private func loadWindow(_ window: HeroStatsWindow, bucket: Int, now: Date) async -> WindowResult {
        let fixed = HeroStatsStore(cache: cache, source: source, mmrPercentile: bucket, windows: [window], percentileSource: percentileSource)
        let loaded = await fixed.load(now: now)
        let origin = loaded.origins[window] ?? .missing(reason: "No hero statistics")
        guard let file = loaded.stats.files[window], file.isUsable else { return WindowResult(entry: nil, origin: origin) }
        let fetchedAt: Date
        switch origin {
        case .downloaded, .notModified: fetchedAt = now
        case .stale, .missing: fetchedAt = cache.read(window, mmrPercentile: bucket)?.fetchedAt ?? .distantPast
        }
        return WindowResult(entry: .init(file: file, etag: nil, fetchedAt: fetchedAt), origin: origin)
    }

    private func embeddedTable(_ entry: HeroStatsCache.Entry?, window: HeroStatsWindow, now: Date) -> MMRPercentileTable? {
        guard let entry, let rows = entry.file.mmrPercentiles, let published = entry.file.lastUpdateDate,
              let table = MMRPercentileTable(rows: rows, window: window,
                sourceURL: FirestoneHeroStatsSource.url(window: window, mmrPercentile: 100).absoluteString,
                updatedAt: published, fetchedAt: entry.fetchedAt), table.isFresh(at: now)
        else { return nil }
        return table
    }

    private func loadPercentiles(_ window: HeroStatsWindow, now: Date) async -> MMRPercentileTable? {
        let saved = cache.readPercentiles(window)
        do {
            let table: MMRPercentileTable
            let etag: String?
            switch try await percentileSource.fetchPercentiles(window: window, etag: saved?.etag) {
            case .notModified:
                guard let saved, let confirmed = MMRPercentileTable(rows: saved.table.rows, window: window,
                    sourceURL: saved.table.sourceURL, updatedAt: saved.table.updatedAt, fetchedAt: now)
                else { throw HeroStatsFetchError.unusable }
                table = confirmed
                etag = saved.etag
            case .body(let data, let token, let published):
                guard data.count <= 64 * 1024, let published,
                      let rows = try? JSONDecoder().decode([MMRPercentileRow].self, from: data),
                      let decoded = MMRPercentileTable(rows: rows, window: window,
                        sourceURL: FirestoneHeroStatsSource.percentilesURL(window: window).absoluteString,
                        updatedAt: published, fetchedAt: now)
                else { throw HeroStatsFetchError.unusable }
                table = decoded
                etag = token
            }
            guard table.isFresh(at: now) else { throw HeroStatsFetchError.unusable }
            try? cache.writePercentiles(table, etag: etag)
            return table
        } catch {
            guard let table = saved?.table, table.isFresh(at: now) else { return nil }
            return table
        }
    }

    private func match(rating: HeroStatsRating?, table: MMRPercentileTable?, now: Date)
        -> (matched: Int?, bucket: Int, reason: HeroStatsMMRSelection.Reason) {
        guard let rating, rating.isRecent(at: now) else { return (nil, 100, .noRecentRating) }
        guard let table, table.isFresh(at: now), let bucket = table.bucket(for: rating.rating) else { return (nil, 100, .noFreshTable) }
        // Current top-one files have very few heroes reaching the existing 300-game window guard.
        // Use the broader top-ten sample, retaining the raw match so the choice stays reviewable.
        return bucket == 1 ? (1, 10, .topOneBroadened) : (bucket, bucket, .mapped)
    }

    private func selection(
        _ window: HeroStatsWindow, bucket: Int, matched: Int?, rating: HeroStatsRating?, table: MMRPercentileTable?,
        entry: HeroStatsCache.Entry?, now: Date, reason: HeroStatsMMRSelection.Reason
    ) -> HeroStatsMMRSelection {
        .init(window: window, mmrPercentile: bucket, matchedPercentile: matched, rating: rating, table: table,
            statsUpdatedAt: entry?.file.lastUpdateDate, fetchedAt: entry?.fetchedAt ?? now, reason: reason)
    }

    private func selectedSet(files: [HeroStatsWindow: FirestoneHeroStatsFile], selections: [HeroStatsWindow: HeroStatsMMRSelection]) -> HeroStatsSet {
        let primary = HeroStatsWindow.preference.first { files[$0] != nil }.flatMap { selections[$0]?.mmrPercentile } ?? 100
        return HeroStatsSet(mmrPercentile: primary, files: files, selections: selections)
    }
}
