import Foundation

public enum CardTurnStatsResponse: Hashable, Sendable {
    case notModified
    case data(Data, etag: String?)
}

public protocol CardTurnStatsSource: Sendable {
    func fetch(etag: String?) async throws -> CardTurnStatsResponse
}

public enum CardTurnStatsError: Error, Equatable, CustomStringConvertible {
    case httpStatus(Int)
    case responseTooLarge
    case invalidResponse
    case unusable

    public var description: String {
        switch self {
        case .httpStatus(let status): "Firestone answered HTTP \(status)"
        case .responseTooLarge: "card statistics exceeded the response size limit"
        case .invalidResponse: "card statistics response was not HTTP"
        case .unusable: "card statistics had no fresh, valid exact-turn evidence"
        }
    }
}

/// Fetches the fixed MMR-25, last-patch aggregate. URLSession decodes Content-Encoding
/// gzip; the `.gz.json` URL suffix itself does not indicate that the returned bytes are gzip.
public struct FirestoneCardTurnStatsSource: CardTurnStatsSource {
    public static let url = CardTurnStats.liveURL
    public let session: URLSession
    public var userAgent: String

    public init(session: URLSession = .shared, userAgent: String = "TavernLens/0.1 (macOS)") {
        self.session = session
        self.userAgent = userAgent
    }

    public func fetch(etag: String?) async throws -> CardTurnStatsResponse {
        var request = URLRequest(url: Self.url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse else { throw CardTurnStatsError.invalidResponse }
        switch http.statusCode {
        case 304: return .notModified
        case 200: break
        case let status: throw CardTurnStatsError.httpStatus(status)
        }
        guard response.expectedContentLength <= Int64(CardTurnStatsStore.maximumResponseBytes) else {
            throw CardTurnStatsError.responseTooLarge
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < CardTurnStatsStore.maximumResponseBytes else {
                throw CardTurnStatsError.responseTooLarge
            }
            data.append(byte)
        }
        return .data(data, etag: http.value(forHTTPHeaderField: "ETag"))
    }
}

/// One atomic file contains the validated snapshot, its ETag and the separate retrieval
/// time. No bundled statistics substitute for a missing download.
public struct CardTurnStatsCache: Sendable {
    public let directory: URL

    public init(directory: URL = CardTurnStatsCache.defaultDirectory) { self.directory = directory }

    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "TavernLens/CardTurnStats", directoryHint: .isDirectory)
    }

    public struct Entry: Codable, Hashable, Sendable {
        public var stats: CardTurnStats
        public var etag: String?
        public var fetchedAt: Date
    }

    private var url: URL { directory.appending(path: "mmr-25-last-patch.json") }

    public func read() -> Entry? {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              size <= CardTurnStatsStore.maximumResponseBytes,
              let data = try? Data(contentsOf: url), data.count <= CardTurnStatsStore.maximumResponseBytes else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    public func write(stats: CardTurnStats, etag: String?, fetchedAt: Date) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Entry(stats: stats, etag: etag, fetchedAt: fetchedAt))
        guard data.count <= CardTurnStatsStore.maximumResponseBytes else { throw CardTurnStatsError.responseTooLarge }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    public func touch(at date: Date) throws {
        guard let cached = read() else { return }
        try write(stats: cached.stats, etag: cached.etag, fetchedAt: date)
    }
}

public struct LoadedCardTurnStats: Hashable, Sendable {
    public enum Origin: Hashable, Sendable {
        case downloaded
        case cache
        case notModified
        case stale(reason: String)
        case missing(reason: String)
    }

    public var stats: CardTurnStats?
    public var origin: Origin
    public var checkedAt: Date

    public var hadFailures: Bool {
        switch origin {
        case .downloaded, .cache, .notModified: false
        case .stale, .missing: true
        }
    }
}

/// A six-hour conditional refresh with a last-good fallback. Source generation time
/// remains authoritative for evidence freshness, even after a successful 304.
public struct CardTurnStatsStore: Sendable {
    public static let refreshInterval: TimeInterval = 6 * 3600
    public static let maximumResponseBytes = 4 * 1024 * 1024

    public let cache: CardTurnStatsCache
    public let source: any CardTurnStatsSource
    public let refreshInterval: TimeInterval

    public init(
        cache: CardTurnStatsCache = CardTurnStatsCache(), source: any CardTurnStatsSource = FirestoneCardTurnStatsSource(),
        refreshInterval: TimeInterval = CardTurnStatsStore.refreshInterval
    ) {
        self.cache = cache
        self.source = source
        self.refreshInterval = refreshInterval
    }

    public func cached() -> CardTurnStats? { cache.read()?.stats }

    public func load(now: Date = Date()) async -> LoadedCardTurnStats {
        let cached = cache.read()
        if let cached, cached.fetchedAt <= now, now.timeIntervalSince(cached.fetchedAt) < refreshInterval,
           usable(cached.stats, now: now) {
            return LoadedCardTurnStats(stats: cached.stats, origin: .cache, checkedAt: now)
        }
        do {
            switch try await source.fetch(etag: cached?.etag) {
            case .notModified:
                guard let cached, usable(cached.stats, now: now) else { throw CardTurnStatsError.unusable }
                try? cache.touch(at: now)
                return LoadedCardTurnStats(stats: cached.stats, origin: .notModified, checkedAt: now)
            case .data(let data, let etag):
                guard data.count <= Self.maximumResponseBytes else { throw CardTurnStatsError.responseTooLarge }
                let stats = try CardTurnStats(json: data)
                guard usable(stats, now: now) else { throw CardTurnStatsError.unusable }
                try? cache.write(stats: stats, etag: etag, fetchedAt: now)
                return LoadedCardTurnStats(stats: stats, origin: .downloaded, checkedAt: now)
            }
        } catch {
            return LoadedCardTurnStats(stats: cached?.stats,
                origin: cached == nil ? .missing(reason: "\(error)") : .stale(reason: "\(error)"), checkedAt: now)
        }
    }

    private func usable(_ stats: CardTurnStats, now: Date) -> Bool {
        guard stats.usable(now: now) else { return false }
        return stats.cardStats.contains { card in
            card.turnStats.contains { row in
                guard let turn = row.turn else { return false }
                return stats.entry(cardID: card.cardId, turn: turn, now: now) != nil
            }
        }
    }
}
