import Foundation
import HSLog

/// A saved replay: one game's own slice of a Power.log, gzip-compressed.
///
/// The file name carries what replaying it needs to reproduce the original exactly:
/// the session folder (it dates the game record) and the line the slice started at
/// (it keeps line numbers the same as in the full log), e.g.
/// `Hearthstone_2026_09_22_21_08_40_L2_S1172082863.power.log.gz`.
public struct ReplayFile: Hashable, Sendable {
    public static let fileExtension = ".power.log.gz"

    public var url: URL
    /// The session folder name the slice came from.
    public var sessionName: String
    /// The slice's first line number in the original Power.log.
    public var line: Int
    public var gameSeed: Int?

    /// Parses a replay file name; nil for anything else.
    public init?(url: URL) {
        let name = url.lastPathComponent
        guard name.hasSuffix(Self.fileExtension) else { return nil }
        let fields = name.dropLast(Self.fileExtension.count).split(separator: "_")
        guard fields.count >= 3, fields[fields.count - 2].hasPrefix("L"), fields[fields.count - 1].hasPrefix("S"),
              let line = Int(fields[fields.count - 2].dropFirst()), line >= 1
        else { return nil }
        let seedText = fields[fields.count - 1].dropFirst()
        self.url = url
        sessionName = fields.dropLast(2).joined(separator: "_")
        self.line = line
        gameSeed = seedText == "none" ? nil : Int(seedText)
        guard seedText == "none" || gameSeed != nil else { return nil }
    }

    static func name(sessionName: String, line: Int, gameSeed: Int?) -> String {
        "\(sessionName)_L\(line)_S\(gameSeed.map(String.init) ?? "none")\(fileExtension)"
    }

    /// The session the slice came from, when its name is a session folder name.
    public func session(timeZone: TimeZone = .current) -> LogSession? {
        LogSession(directory: URL(filePath: "/Logs").appending(path: sessionName), timeZone: timeZone)
    }
}

/// Compressed per-game log slices, for replaying a game in the debug window after its
/// Hearthstone logs are gone (bug reports, new test fixtures). In
/// `~/Library/Application Support/TavernLens/Replays` by default.
public struct ReplayStore: Sendable {
    public static let defaultLimit = 40

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static var standard: ReplayStore {
        ReplayStore(directory: URL.applicationSupportDirectory.appending(path: "TavernLens/Replays", directoryHint: .isDirectory))
    }

    /// Every replay, oldest first (by session, then position in the log).
    public func all(timeZone: TimeZone = .current) -> [ReplayFile] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap(ReplayFile.init(url:)).sorted {
            let left = ($0.session(timeZone: timeZone)?.started ?? .distantPast, $0.sessionName, $0.line)
            let right = ($1.session(timeZone: timeZone)?.started ?? .distantPast, $1.sessionName, $1.line)
            return left < right
        }
    }

    /// Whether the game at `line` of that session has a replay.
    public func contains(sessionName: String, line: Int, gameSeed: Int?) -> Bool {
        let url = directory.appending(path: ReplayFile.name(sessionName: sessionName, line: line, gameSeed: gameSeed))
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Compresses and saves one game's slice of a session's Power.log.
    @discardableResult
    public func save(_ slice: PowerLogGameSlice, of powerLog: Data, sessionName: String) throws -> ReplayFile {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: ReplayFile.name(sessionName: sessionName, line: slice.line, gameSeed: slice.gameSeed))
        try Gzip.compress(powerLog.subdata(in: slice.byteRange)).write(to: url, options: .atomic)
        return ReplayFile(url: url)!
    }

    /// Keeps the newest `limit` replays and deletes the rest; returns what was deleted.
    @discardableResult
    public func prune(keeping limit: Int, timeZone: TimeZone = .current) -> [ReplayFile] {
        let replays = all(timeZone: timeZone)
        let excess = Array(replays.prefix(max(0, replays.count - max(0, limit))))
        return excess.filter { (try? FileManager.default.removeItem(at: $0.url)) != nil }
    }
}

extension TavernEngine {
    /// Replays a saved game slice exactly as the full log would: dated from its session,
    /// with the original line numbers.
    public static func replay(_ replay: ReplayFile, cards: CardDB? = nil, timeZone: TimeZone = .current) throws -> ReplayResult {
        let data = try Gzip.decompress(Data(contentsOf: replay.url))
        var engine = TavernEngine(cards: cards, session: replay.session(timeZone: timeZone), timeZone: timeZone)
        engine.skipLines(replay.line - 1)
        var splitter = LogLineSplitter()
        splitter.append(data) { engine.ingest($0) }
        if let last = splitter.finish() { engine.ingest(last) }
        engine.finish()
        return engine.replayResult
    }
}
