import Foundation

/// An observed rating, never inferred from a match result.
public struct RatingReading: Codable, Hashable, Identifiable, Sendable {
    public enum Source: String, Codable, Hashable, Sendable {
        case manual, screen

        public var label: String { self == .manual ? "Entered" : "Screen" }
    }

    public let id: UUID
    public let recordedAt: Date
    public let rating: Int
    public let source: Source
    public let gameSeed: Int?

    public init(id: UUID = UUID(), recordedAt: Date = Date(), rating: Int, source: Source, gameSeed: Int? = nil) throws {
        guard rating >= 0 else { throw RatingHistoryError.invalidRating }
        guard recordedAt.timeIntervalSince1970.isFinite else { throw RatingHistoryError.invalidDate }
        self.id = id
        self.recordedAt = recordedAt
        self.rating = rating
        self.source = source
        self.gameSeed = gameSeed
    }

    private enum CodingKeys: String, CodingKey { case id, recordedAt, rating, source, gameSeed }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: c.decode(UUID.self, forKey: .id), recordedAt: c.decode(Date.self, forKey: .recordedAt),
                      rating: c.decode(Int.self, forKey: .rating), source: c.decode(Source.self, forKey: .source),
                      gameSeed: c.decodeIfPresent(Int.self, forKey: .gameSeed))
    }
}

public enum RatingHistoryError: Error, LocalizedError, Equatable, Sendable {
    case invalidRating, invalidDate, duplicateID, missingReading, unsupportedFormat(Int)
    case unreadableHistory(String), saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRating: "Enter a whole-number rating of 0 or greater."
        case .invalidDate: "The reading needs a valid date."
        case .duplicateID: "The rating history contains duplicate reading IDs."
        case .missingReading: "That rating reading is no longer in the history. Refresh and try again."
        case .unsupportedFormat(let version): "Rating history format \(version) is not supported by this app."
        case .unreadableHistory(let detail): "Couldn’t read rating history. The existing file has not been changed. \(detail)"
        case .saveFailed(let detail): "Couldn’t save the rating reading. \(detail)"
        }
    }
}

public struct RatingHistory: Codable, Equatable, Sendable {
    public static let currentFormat = 1
    public private(set) var readings: [RatingReading] = []

    public init() {}

    public init(readings: [RatingReading]) throws {
        guard Set(readings.map(\.id)).count == readings.count else { throw RatingHistoryError.duplicateID }
        self.readings = Self.ordered(readings)
    }

    /// Ignore only an incoming screen sighting equal to a neighboring screen reading
    /// from the same game. Explicit entries and already saved observations are preserved.
    @discardableResult
    public mutating func record(_ reading: RatingReading) throws -> Bool {
        guard !readings.contains(where: { $0.id == reading.id }) else { throw RatingHistoryError.duplicateID }
        let next = Self.ordered(readings + [reading])
        if reading.source == .screen, let index = next.firstIndex(where: { $0.id == reading.id }),
           [index - 1, index + 1].contains(where: { neighbor in
               next.indices.contains(neighbor) && next[neighbor].source == .screen
                   && next[neighbor].rating == reading.rating && next[neighbor].gameSeed == reading.gameSeed
           }) { return false }
        readings = next
        return true
    }

    /// Keeps the original observation time/game while marking the corrected value as entered.
    public mutating func correct(id: UUID, rating: Int) throws {
        guard let index = readings.firstIndex(where: { $0.id == id }) else { throw RatingHistoryError.missingReading }
        let old = readings[index]
        readings[index] = try RatingReading(id: old.id, recordedAt: old.recordedAt, rating: rating,
                                            source: .manual, gameSeed: old.gameSeed)
    }

    public var latest: RatingReading? { readings.last }
    public var highest: Int? { readings.map(\.rating).max() }
    public var latestChange: Int? {
        guard readings.count >= 2 else { return nil }
        return readings[readings.count - 1].rating - readings[readings.count - 2].rating
    }

    private static func ordered(_ readings: [RatingReading]) -> [RatingReading] {
        // Preserve insertion order for readings with the same timestamp.
        readings.enumerated().sorted {
            $0.element.recordedAt == $1.element.recordedAt ? $0.offset < $1.offset
                : $0.element.recordedAt < $1.element.recordedAt
        }.map(\.element)
    }

    private enum CodingKeys: String, CodingKey { case format, readings }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let format = try c.decode(Int.self, forKey: .format)
        guard format == Self.currentFormat else { throw RatingHistoryError.unsupportedFormat(format) }
        try self.init(readings: c.decode([RatingReading].self, forKey: .readings))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentFormat, forKey: .format)
        try c.encode(readings, forKey: .readings)
    }
}

/// Injectable byte storage lets the history's failure paths be tested without touching live data.
public protocol RatingHistoryPersistence: Sendable {
    /// nil means the file is absent; unreadable data must throw, not masquerade as an empty store.
    func read() throws -> Data?
    func write(_ data: Data) throws
}

public struct RatingHistoryFilePersistence: RatingHistoryPersistence {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func read() throws -> Data? {
        do { return try Data(contentsOf: url) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }

    public func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

/// Serializes disk operations away from the main actor. Every mutation reloads and validates
/// the existing file before an atomic write, so malformed or newer history is never replaced.
public actor RatingHistoryStore {
    private let persistence: any RatingHistoryPersistence

    public init(persistence: any RatingHistoryPersistence) { self.persistence = persistence }
    public init(url: URL) { persistence = RatingHistoryFilePersistence(url: url) }

    public static var standardURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSHomeDirectory()).appending(path: "Library/Application Support")
        return support.appending(path: "TavernLens/RatingHistory.json")
    }

    public static var standard: RatingHistoryStore { RatingHistoryStore(url: standardURL) }

    public func load() throws -> RatingHistory {
        do {
            guard let data = try persistence.read() else { return RatingHistory() }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            return try decoder.decode(RatingHistory.self, from: data)
        } catch {
            throw RatingHistoryError.unreadableHistory(error.localizedDescription)
        }
    }

    public func record(_ reading: RatingReading) throws -> RatingHistory {
        var history = try load()
        if try history.record(reading) { try save(history) }
        return history
    }

    public func correct(id: UUID, rating: Int) throws -> RatingHistory {
        var history = try load()
        try history.correct(id: id, rating: rating)
        try save(history)
        return history
    }

    private func save(_ history: RatingHistory) throws {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try persistence.write(encoder.encode(history))
        } catch {
            throw RatingHistoryError.saveFailed(error.localizedDescription)
        }
    }
}
