import Foundation

/// HSReplay's live Battlegrounds meta period
/// (`https://hsreplay.net/api/v1/battlegrounds/meta_periods/live/`): the tribes in rotation
/// and per-card tag overrides for server-side pool changes. HDT and HSTracker patch their
/// card data with it. It is undocumented and best-effort; our override file wins over it.
public struct MetaPeriod: Codable, Hashable, Sendable {
    public struct TagOverride: Codable, Hashable, Sendable {
        public var dbfID: Int
        public var tag: Int
        public var value: Int

        public init(dbfID: Int, tag: Int, value: Int) {
            self.dbfID = dbfID
            self.tag = tag
            self.value = value
        }

        private enum CodingKeys: String, CodingKey {
            case dbfID = "dbf_id"
            case tag, value
        }
    }

    /// `period_start` (milliseconds since 1970 in the JSON).
    public var periodStart: Date
    /// E.g. "Real 36.6.1".
    public var name: String
    public var seasonNumber: Int?
    public var mechanics: [String]
    /// `Race` numbers in rotation.
    public var minionTypes: [Int]
    public var tagOverrides: [TagOverride]

    public init(
        periodStart: Date, name: String, seasonNumber: Int? = nil, mechanics: [String] = [], minionTypes: [Int],
        tagOverrides: [TagOverride] = []
    ) {
        self.periodStart = periodStart
        self.name = name
        self.seasonNumber = seasonNumber
        self.mechanics = mechanics
        self.minionTypes = minionTypes
        self.tagOverrides = tagOverrides
    }

    private enum CodingKeys: String, CodingKey {
        case periodStart = "period_start"
        case name
        case seasonNumber = "season_number"
        case mechanics
        case minionTypes = "minion_types"
        case tagOverrides = "tag_overrides"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let milliseconds = try c.decode(Double.self, forKey: .periodStart)
        periodStart = Date(timeIntervalSince1970: milliseconds / 1000)
        name = try c.decode(String.self, forKey: .name)
        seasonNumber = try c.decodeIfPresent(Int.self, forKey: .seasonNumber)
        mechanics = try c.decodeIfPresent([String].self, forKey: .mechanics) ?? []
        minionTypes = try c.decode([Int].self, forKey: .minionTypes)
        tagOverrides = try c.decodeIfPresent([TagOverride].self, forKey: .tagOverrides) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode((periodStart.timeIntervalSince1970 * 1000).rounded(), forKey: .periodStart)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(seasonNumber, forKey: .seasonNumber)
        try c.encode(mechanics, forKey: .mechanics)
        try c.encode(minionTypes, forKey: .minionTypes)
        try c.encode(tagOverrides, forKey: .tagOverrides)
    }

    public init(json: Data) throws {
        self = try JSONDecoder().decode(MetaPeriod.self, from: json)
    }

    public var tribesInRotation: [HS.Race] { minionTypes.map(HS.Race.init(rawValue:)) }

    /// The overridden value of `tag` on the card, if the period overrides it.
    public func override(dbfID: Int, tag: Int) -> Int? {
        tagOverrides.last { $0.dbfID == dbfID && $0.tag == tag }?.value
    }

    /// The copy shipped with the app (fetched 2026-09-23), for a first launch offline.
    public static func bundled() -> MetaPeriod? {
        guard let url = HSDataResources.url("bg-pool/hsreplay-meta-period-live.json") else { return nil }
        return try? MetaPeriod(json: Data(contentsOf: url))
    }
}

/// Where the live meta period is downloaded from.
public protocol MetaPeriodSource: Sendable {
    /// The raw JSON of the live meta period.
    func liveMetaPeriodJSON() async throws -> Data
}

public enum MetaPeriodError: Error, Equatable, CustomStringConvertible {
    case httpStatus(Int)

    public var description: String {
        switch self {
        case .httpStatus(403): "HSReplay answered HTTP 403 (its bot protection turned the request away)"
        case .httpStatus(let status): "HSReplay answered HTTP \(status)"
        }
    }
}

/// HSReplay's unauthenticated live meta-period endpoint.
///
/// HSReplay sits behind Cloudflare, which (as of 2026-09-23) answers most clients with a
/// 403 challenge; the pool then comes from the cached or bundled copy plus our override
/// file. `userAgent` is configurable for that reason.
public struct HSReplayMetaPeriodSource: MetaPeriodSource {
    public static let liveURL = URL(string: "https://hsreplay.net/api/v1/battlegrounds/meta_periods/live/")!

    public var url: URL
    public var userAgent: String

    public init(url: URL = HSReplayMetaPeriodSource.liveURL, userAgent: String = "TavernLens/0.1 (macOS)") {
        self.url = url
        self.userAgent = userAgent
    }

    public func liveMetaPeriodJSON() async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard status == 200 else { throw MetaPeriodError.httpStatus(status) }
        return data
    }
}

/// The last good meta periods on disk, one file per period (`<period_start ms>.json`).
/// A file's modification date is when it was last fetched.
public struct MetaPeriodCache: Sendable {
    public let directory: URL
    /// How many periods to keep.
    public let limit: Int

    public init(directory: URL = MetaPeriodCache.defaultDirectory, limit: Int = 3) {
        self.directory = directory
        self.limit = max(1, limit)
    }

    /// `~/Library/Application Support/TavernLens/MetaPeriod`.
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "TavernLens/MetaPeriod", directoryHint: .isDirectory)
    }

    /// The newest cached period and when it was fetched.
    public func latest() -> (period: MetaPeriod, fetchedAt: Date)? {
        entries().first.flatMap { url in
            guard let period = try? MetaPeriod(json: Data(contentsOf: url)) else { return nil }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return (period, date ?? .distantPast)
        }
    }

    /// Stores a fetched period (refreshing its fetch date) and drops the oldest beyond `limit`.
    public func write(_ data: Data, period: MetaPeriod, fetchedAt: Date) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = Int64((period.periodStart.timeIntervalSince1970 * 1000).rounded())
        let url = directory.appending(path: "\(key).json")
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: fetchedAt], ofItemAtPath: url.path(percentEncoded: false))
        for old in entries().dropFirst(limit) { try? FileManager.default.removeItem(at: old) }
    }

    /// Cached files, newest period first.
    private func entries() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { url -> (Int64, URL)? in
            guard url.pathExtension == "json", let key = Int64(url.deletingPathExtension().lastPathComponent) else { return nil }
            return (key, url)
        }
        .sorted { $0.0 > $1.0 }
        .map(\.1)
    }
}

/// A meta period as loaded, and where it came from.
public struct LoadedMetaPeriod: Hashable, Sendable {
    public enum Origin: Hashable, Sendable {
        /// Fetched now and cached.
        case downloaded
        /// Fetched recently enough (within the refresh interval) that it wasn't fetched again.
        case cache
        /// The fetch failed; the newest cached copy, however old.
        case stale(reason: String)
        /// The fetch failed and nothing is cached: the copy shipped with the app.
        case bundled(reason: String)
    }

    public var period: MetaPeriod
    public var origin: Origin
    /// When the copy was fetched; nil for the bundled copy.
    public var fetchedAt: Date?

    public var isStale: Bool {
        switch origin {
        case .downloaded, .cache: false
        case .stale, .bundled: true
        }
    }
}

/// Loads HSReplay's live meta period: from the cache while it's fresh, otherwise fetched
/// and cached, falling back to the last good copy and then to the bundled copy.
public struct MetaPeriodStore: Sendable {
    /// Refresh at app start and every 6 hours (research §A.8).
    public static let refreshInterval: TimeInterval = 6 * 60 * 60

    public let cache: MetaPeriodCache
    public let source: any MetaPeriodSource
    public let refreshInterval: TimeInterval

    public init(
        cache: MetaPeriodCache = MetaPeriodCache(), source: any MetaPeriodSource = HSReplayMetaPeriodSource(),
        refreshInterval: TimeInterval = MetaPeriodStore.refreshInterval
    ) {
        self.cache = cache
        self.source = source
        self.refreshInterval = refreshInterval
    }

    /// Nil only when the fetch fails, nothing is cached and there is no bundled copy.
    public func load(now: Date = Date(), bundled: MetaPeriod? = MetaPeriod.bundled()) async -> LoadedMetaPeriod? {
        let cached = cache.latest()
        if let cached, now.timeIntervalSince(cached.fetchedAt) < refreshInterval, cached.fetchedAt <= now {
            return LoadedMetaPeriod(period: cached.period, origin: .cache, fetchedAt: cached.fetchedAt)
        }
        let reason: String
        do {
            let data = try await source.liveMetaPeriodJSON()
            let period = try MetaPeriod(json: data)
            try? cache.write(data, period: period, fetchedAt: now)
            return LoadedMetaPeriod(period: period, origin: .downloaded, fetchedAt: now)
        } catch {
            reason = "\(error)"
        }
        // The newer of the last good copy and the bundled one.
        if let cached, cached.period.periodStart >= (bundled?.periodStart ?? .distantPast) {
            return LoadedMetaPeriod(period: cached.period, origin: .stale(reason: reason), fetchedAt: cached.fetchedAt)
        }
        return bundled.map { LoadedMetaPeriod(period: $0, origin: .bundled(reason: reason), fetchedAt: nil) }
    }
}
