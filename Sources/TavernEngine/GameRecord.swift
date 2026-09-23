import BGState
import Foundation

@_exported import struct BGState.BGGameJournal
@_exported import struct BGState.BGTurnSnapshot
@_exported import struct BGState.BGReconnect
@_exported import struct BGState.BGOpponentBoard
@_exported import enum BGState.BGGameOutcome

/// The compact, permanent record of one solo Battlegrounds game, keyed by `GAME_SEED`:
/// its summary and result, a snapshot at the end of every recruit phase, and every
/// opponent board seen. It outlives the Hearthstone logs it was read from.
///
/// Records are written as the game reaches checkpoints (start, each turn, each combat,
/// the end), so a game whose log stopped (the client quit or crashed) is kept as
/// `inProgress`; it becomes `abandoned` once a different game starts.
public struct GameRecord: Codable, Hashable, Sendable {
    public static let currentFormat = 1

    public var format = GameRecord.currentFormat
    public var summary: BGGameRecord
    public var journal: BGGameJournal
    /// The session folders (client launches) the game was read from, in order.
    public var sessions: [String]
    /// When the game started and ended, from the session folder's date and the log's
    /// times of day (with midnight rollover); nil when replayed without a session.
    public var startedAt: Date?
    public var endedAt: Date?
    /// The time of the latest line of this game read so far.
    public var updatedAt: Date?

    public init(
        summary: BGGameRecord, journal: BGGameJournal, sessions: [String] = [], startedAt: Date? = nil,
        endedAt: Date? = nil, updatedAt: Date? = nil
    ) {
        self.summary = summary
        self.journal = journal
        self.sessions = sessions
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.updatedAt = updatedAt
    }

    public var gameSeed: Int? { summary.gameSeed }
    public var outcome: BGGameOutcome { summary.outcome }
}

/// Game records on disk: one JSON file per game, named after its `GAME_SEED`, in
/// `~/Library/Application Support/TavernLens/Games` by default.
///
/// Writes are atomic, so a crash never leaves a half-written record, and saving a game
/// again replaces its file.
public struct GameRecordStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The app's store in Application Support.
    public static var standard: GameRecordStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSHomeDirectory()).appending(path: "Library/Application Support")
        return GameRecordStore(directory: support.appending(path: "TavernLens/Games", directoryHint: .isDirectory))
    }

    /// The file a record lives in.
    public func url(for record: GameRecord) -> URL {
        let name: String
        if let seed = record.gameSeed {
            name = "game-\(seed).json"
        } else {
            // Every real game has a seed; this keeps an unseeded one from overwriting others.
            let session = record.sessions.first ?? "unknown"
            name = "game-unseeded-\(session)-\(record.summary.start.line).json"
        }
        return directory.appending(path: name)
    }

    public func save(_ record: GameRecord) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(record).write(to: url(for: record), options: .atomic)
    }

    public func load(seed: Int) -> GameRecord? {
        let url = directory.appending(path: "game-\(seed).json")
        return (try? Data(contentsOf: url)).flatMap { try? Self.decoder.decode(GameRecord.self, from: $0) }
    }

    /// Every readable record, oldest first. Unreadable files are skipped.
    public func all() -> [GameRecord] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("game-") && $0.pathExtension == "json" }
            .compactMap { (try? Data(contentsOf: $0)).flatMap { try? Self.decoder.decode(GameRecord.self, from: $0) } }
            .sorted { ($0.startedAt ?? .distantPast, $0.gameSeed ?? 0) < ($1.startedAt ?? .distantPast, $1.gameSeed ?? 0) }
    }

    /// The most recently updated game still in progress: the one a client restart may resume.
    public func latestInProgress() -> GameRecord? {
        all().filter { $0.outcome == .inProgress }
            .max { ($0.updatedAt ?? .distantPast) < ($1.updatedAt ?? .distantPast) }
    }

    /// Dates are ISO 8601 with milliseconds.
    static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(dateStyle))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? dateStyle.parse(text) ?? Date.ISO8601FormatStyle().parse(text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not an ISO 8601 date: \(text)"))
        }
        return decoder
    }()
}
