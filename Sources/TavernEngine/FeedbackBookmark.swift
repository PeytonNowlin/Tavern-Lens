import Foundation
import HSLog

/// The stretch of a Power.log that rebuilds one moment, read the way the live app read
/// it: from its entry point (`PowerLogEntryPoint`) with publishing suppressed, up to and
/// including `endLine`, then published once.
///
/// Line numbers are the file's own (1-based), even when reading starts at a byte offset,
/// so positions in the replayed state match the live ones.
public struct LogCut: Codable, Hashable, Sendable {
    /// The session folder (`Hearthstone_YYYY_MM_DD_HH_MM_SS`) the log is from; it dates records.
    public var session: String?
    public var gameSeed: Int?
    /// The first line read, and the byte offset it starts at (nil when unknown: found by counting lines).
    public var startLine: Int
    public var startByteOffset: UInt64?
    /// The last line read, and the byte offset just past it (nil until located).
    public var endLine: Int
    public var endByteOffset: UInt64?

    public init(
        session: String?, gameSeed: Int?, startLine: Int, startByteOffset: UInt64?, endLine: Int,
        endByteOffset: UInt64? = nil
    ) {
        self.session = session
        self.gameSeed = gameSeed
        self.startLine = startLine
        self.startByteOffset = startByteOffset
        self.endLine = endLine
        self.endByteOffset = endByteOffset
    }

    /// Fills in the byte offsets from the log at `url` (lines are append-only, so they never move).
    public func locating(in url: URL) -> LogCut {
        var cut = self
        if cut.startByteOffset == nil {
            cut.startByteOffset = startLine <= 1 ? 0 : LogLineOffsets.end(ofLine: startLine - 1, in: url)
        }
        if cut.endByteOffset == nil, let start = cut.startByteOffset {
            cut.endByteOffset = LogLineOffsets.end(ofLine: endLine, in: url, startLine: startLine, startOffset: start)
        }
        return cut
    }
}

/// What the overlay showed when a bookmark was taken.
public struct BookmarkOverlay: Codable, Hashable, Sendable {
    /// The overlay panel was on screen (Hearthstone frontmost, a window found, not hidden).
    public var visible: Bool
    public var hiddenByUser: Bool
    public var showsLayoutGuides: Bool
    /// Hearthstone's client area, in points, and whether it was fullscreen.
    public var contentWidth: Double?
    public var contentHeight: Double?
    public var fullscreen: Bool?
    /// `LayoutConstants.version` in use.
    public var layoutVersion: String?
    /// The panels drawn, e.g. `hud`, `opponentPanel`, `nextOpponentPreview`.
    public var panels: [String]
    /// The opponent whose leaderboard portrait was hovered.
    public var hoveredPlayerID: Int?
    /// The overlay was drawing the bookmarked state; false when its ~10 Hz update hadn't
    /// caught up with the engine yet.
    public var drewShownState: Bool

    public init(
        visible: Bool, hiddenByUser: Bool, showsLayoutGuides: Bool, contentWidth: Double? = nil,
        contentHeight: Double? = nil, fullscreen: Bool? = nil, layoutVersion: String? = nil, panels: [String] = [],
        hoveredPlayerID: Int? = nil, drewShownState: Bool
    ) {
        self.visible = visible
        self.hiddenByUser = hiddenByUser
        self.showsLayoutGuides = showsLayoutGuides
        self.contentWidth = contentWidth
        self.contentHeight = contentHeight
        self.fullscreen = fullscreen
        self.layoutVersion = layoutVersion
        self.panels = panels
        self.hoveredPlayerID = hoveredPlayerID
        self.drewShownState = drewShownState
    }
}

/// A moment the player bookmarked (⌃⌥F) with a one-line note: the full state shown, and
/// enough to replay the log to exactly that state (`TavernEngine.replay(_:powerLog:resuming:)`).
/// Stored in its game's record.
public struct FeedbackBookmark: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// The wall-clock time the hotkey was pressed.
    public var createdAt: Date
    public var note: String
    /// Where the moment is in the log.
    public var cut: LogCut
    /// The Power.log's path when the bookmark was taken.
    public var powerLog: String?
    /// The state shown, and the log position it was published at.
    public var shown: TimelineEntry
    /// The in-progress record the engine carried in at session start (a game resumed
    /// after a client or app restart), without its bookmarks; replays need it too.
    public var resumed: GameRecord?
    public var overlay: BookmarkOverlay?
    /// What the advisor showed (recruit only): its ranked suggestions and how far scoring had got,
    /// which `TavernEngine.replayAdvice` reproduces.
    public var advice: AdviceView?
    /// The state the advice was for (its `fingerprint`'s request), so the case can be re-scored
    /// under other weights without the log (`AdvisorTuning`).
    public var adviceRequest: AdvisorRequest?

    public init(
        id: UUID = UUID(), createdAt: Date = Date(), note: String = "", cut: LogCut, powerLog: String? = nil,
        shown: TimelineEntry, resumed: GameRecord? = nil, overlay: BookmarkOverlay? = nil, advice: AdviceView? = nil,
        adviceRequest: AdvisorRequest? = nil
    ) {
        self.id = id
        // Whole seconds, which survive the record store's ISO 8601 text exactly.
        self.createdAt = Date(timeIntervalSinceReferenceDate: createdAt.timeIntervalSinceReferenceDate.rounded(.down))
        self.note = note
        self.cut = cut
        self.powerLog = powerLog
        self.shown = shown
        self.resumed = resumed
        self.overlay = overlay
        self.advice = advice
        self.adviceRequest = adviceRequest
    }

    public var gameSeed: Int? { cut.gameSeed }
    public var bgTurn: Int? { shown.state.game?.bgTurn }
    public var phase: BGPhase? { shown.state.game?.phase }
}

public enum BookmarkReplayError: Error, Equatable, CustomStringConvertible {
    /// The log ends before the cut's last line.
    case logTooShort(lines: Int, needed: Int)
    case invalidCut
    /// An exported case didn't replay to the bookmarked state.
    case replayDiffers
    /// The case JSON would contain a `Name#1234` BattleTag (in the note?).
    case containsBattleTag
    case missingLog(String)
    /// The advice shown was for another state than the bookmarked one (it was still catching up).
    case adviceForAnotherState

    public var description: String {
        switch self {
        case .logTooShort(let lines, let needed): "the log has \(lines) lines; the bookmark needs \(needed)"
        case .invalidCut: "the bookmark's log cut is invalid"
        case .replayDiffers: "replaying the log doesn't reach the bookmarked state"
        case .containsBattleTag: "the case would contain a BattleTag; remove it from the note"
        case .missingLog(let path): "the log \(path) isn't there any more"
        case .adviceForAnotherState: "the advice shown was for an earlier state than the bookmarked one"
        }
    }
}

extension TavernEngine {
    /// Replays `cut` of the Power.log at `url` the way the live pipeline read it: carry in
    /// `record` (the bookmark's `resumed`), start at the cut's first line, catch up to its
    /// last, and publish once. The returned engine's `state` is the moment.
    public static func replay(
        _ cut: LogCut, powerLog url: URL, resuming record: GameRecord? = nil, cards: CardDB? = nil,
        pool: MinionPool? = nil, builds: BuildCatalog? = nil, timeZone: TimeZone = .current
    ) throws -> TavernEngine {
        guard cut.startLine >= 1, cut.endLine >= cut.startLine else { throw BookmarkReplayError.invalidCut }
        let session = cut.session.flatMap {
            LogSession(directory: URL(filePath: "/", directoryHint: .isDirectory).appending(path: $0), timeZone: timeZone)
        }
        var engine = TavernEngine(cards: cards, pool: pool, builds: builds, session: session, timeZone: timeZone)
        if let record { engine.resume(record) }
        let start = cut.startByteOffset ?? cut.locating(in: url).startByteOffset
        guard let start else { throw BookmarkReplayError.logTooShort(lines: 0, needed: cut.startLine) }
        engine.start(at: PowerLogEntryPoint(byteOffset: start, line: cut.startLine, gameSeed: cut.gameSeed))
        engine.beginCatchUp()
        struct Reached: Error {}
        do {
            try LogFileReader.forEachLine(in: url, from: start) { line in
                engine.ingest(line)
                if engine.linesRead >= cut.endLine { throw Reached() }
            }
            throw BookmarkReplayError.logTooShort(lines: engine.linesRead, needed: cut.endLine)
        } catch is Reached {}
        engine.endCatchUp()
        return engine
    }

    /// Re-scores `advice` for the moment `cut` replays to, exactly as far as it was scored (same
    /// plan, seed and number of evaluations), so it comes out identical. Nil when there's no
    /// advice; throws `adviceForAnotherState` when the advice was for an earlier state.
    ///
    /// The engine must be set up as it was live (card data, pool and build catalog), since the
    /// request carries the builds and the lobby's tribes; a bookmark that kept its
    /// `adviceRequest` can be re-scored without the log at all (`AdviceView.replaying`).
    public static func replayAdvice(
        _ advice: AdviceView?, cut: LogCut, powerLog url: URL, resuming record: GameRecord? = nil,
        cards: CardDB? = nil, pool: MinionPool? = nil, builds: BuildCatalog? = nil, simulate: AdvisorEvaluation.Simulate
    ) async throws -> AdviceView? {
        guard let advice else { return nil }
        let engine = try replay(cut, powerLog: url, resuming: record, cards: cards, pool: pool, builds: builds, timeZone: .gmt)
        guard let request = engine.advisorRequest, AdviceView.fingerprint(of: request) == advice.fingerprint else {
            throw BookmarkReplayError.adviceForAnotherState
        }
        return try await advice.replaying(request, simulate: simulate)
    }

    /// Replays a bookmark's moment from its Power.log (or another copy of it at `url`).
    /// With a pool, the moment's tribes come out as they did live if the pool is the same.
    public static func replay(
        _ bookmark: FeedbackBookmark, powerLog url: URL, cards: CardDB? = nil, pool: MinionPool? = nil
    ) throws -> TavernEngine {
        try replay(bookmark.cut, powerLog: url, resuming: bookmark.resumed, cards: cards, pool: pool)
    }
}

// MARK: - Golden cases

/// A bookmark turned into a regression test: replaying `cut` of `log` must publish `expected`.
///
/// The case JSON is committed (`Tests/TavernEngineTests/Golden/Bookmarks/<name>.json`), so it's
/// redacted: opponents' display names become `Opp-P<PlayerID>`. The log holds BattleTags and
/// stays in the git-ignored fixtures directory.
public struct BookmarkGoldenCase: Codable, Hashable, Sendable {
    public static let currentFormat = 1

    public var format = BookmarkGoldenCase.currentFormat
    public var name: String
    public var note: String
    public var bookmarkID: UUID?
    /// The Power.log, relative to the private fixtures directory (`fixtures/private-logs`).
    public var log: String
    public var cut: LogCut
    /// Redacted like `expected`.
    public var resumed: GameRecord?
    public var expected: TimelineEntry
    /// The advice shown at the moment, when there was any: replaying the case re-scores it
    /// (`TavernEngine.replayAdvice`) and must give exactly this.
    public var expectedAdvice: AdviceView?
    /// The state `expectedAdvice` is for, so the case can be re-scored under other weights
    /// without its log (`AdvisorTuning`); it holds no names.
    public var adviceRequest: AdvisorRequest?

    public init(
        name: String, note: String, bookmarkID: UUID? = nil, log: String, cut: LogCut, resumed: GameRecord? = nil,
        expected: TimelineEntry, expectedAdvice: AdviceView? = nil, adviceRequest: AdvisorRequest? = nil
    ) {
        self.name = name
        self.note = note
        self.bookmarkID = bookmarkID
        self.log = log
        self.cut = cut
        self.resumed = resumed.map { $0.redactingNames() }
        self.expected = expected.redactingNames()
        self.expectedAdvice = expectedAdvice
        self.adviceRequest = adviceRequest
    }

    /// Replays the case from its log and returns the published moment, redacted like `expected`.
    public func replay(powerLog url: URL, cards: CardDB? = nil) throws -> TimelineEntry? {
        let engine = try TavernEngine.replay(cut, powerLog: url, resuming: resumed, cards: cards, timeZone: .gmt)
        return engine.timeline.last?.redactingNames()
    }

    /// Pretty-printed with sorted keys, and dates as the record store writes them.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = GameRecordStore.encoder.dateEncodingStrategy
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }

    public static func decode(_ data: Data) throws -> BookmarkGoldenCase {
        try GameRecordStore.decoder.decode(BookmarkGoldenCase.self, from: data)
    }

    /// `Name#1234`-shaped text.
    public static func containsBattleTag(_ text: String) -> Bool {
        text.contains(/[\p{L}\p{N}_]+#\d{3,}/)
    }
}

/// Exports bookmarks as golden cases into a checkout of this repository.
public enum BookmarkExport {
    /// Where committed cases live, relative to the repository root.
    public static let casesDirectory = "Tests/TavernEngineTests/Golden/Bookmarks"
    /// The private fixtures directory, relative to the repository root (git-ignored).
    public static let fixturesDirectory = "fixtures/private-logs"

    /// A file-name-safe default name, e.g. `bookmark-1172082863-t6-combat-3f2a9c`.
    public static func defaultName(for bookmark: FeedbackBookmark) -> String {
        var parts = ["bookmark"]
        if let seed = bookmark.gameSeed { parts.append(String(seed)) }
        if let turn = bookmark.bgTurn { parts.append("t\(turn)") }
        if let phase = bookmark.phase { parts.append(phase.rawValue.lowercased()) }
        parts.append(String(bookmark.id.uuidString.lowercased().prefix(6)))
        return parts.joined(separator: "-")
    }

    /// Writes `bookmark` as a golden case under `root`:
    /// - the lines it replays, copied out of `powerLog`, to
    ///   `fixtures/private-logs/bookmarks/<name>/Power.log` (private, git-ignored);
    /// - the redacted case to `Tests/TavernEngineTests/Golden/Bookmarks/<name>.json` (committed).
    ///
    /// The copy is replayed before anything is written, and the export fails unless it
    /// reaches the bookmarked state.
    @discardableResult
    public static func export(
        _ bookmark: FeedbackBookmark, powerLog: URL, name: String? = nil, into root: URL
    ) throws -> (goldenCase: BookmarkGoldenCase, caseFile: URL, logFile: URL) {
        let name = sanitized(name ?? defaultName(for: bookmark))
        guard FileManager.default.fileExists(atPath: powerLog.path(percentEncoded: false)) else {
            throw BookmarkReplayError.missingLog(powerLog.path(percentEncoded: false))
        }
        let cut = bookmark.cut.locating(in: powerLog)
        guard let start = cut.startByteOffset, let end = cut.endByteOffset, end >= start else {
            throw BookmarkReplayError.logTooShort(lines: 0, needed: cut.endLine)
        }
        let slice = try bytes(of: powerLog, from: start, to: end)
        var sliceCut = cut
        sliceCut.startByteOffset = 0
        sliceCut.endByteOffset = UInt64(slice.count)

        let logPath = "bookmarks/\(name)/Power.log"
        let goldenCase = BookmarkGoldenCase(
            name: name, note: bookmark.note, bookmarkID: bookmark.id, log: logPath, cut: sliceCut,
            resumed: bookmark.resumed, expected: bookmark.shown, expectedAdvice: bookmark.advice,
            adviceRequest: bookmark.adviceRequest
        )
        let json = try goldenCase.encoded()
        guard !BookmarkGoldenCase.containsBattleTag(String(decoding: json, as: UTF8.self)) else {
            throw BookmarkReplayError.containsBattleTag
        }

        let logFile = root.appending(path: fixturesDirectory).appending(path: logPath)
        let caseFile = root.appending(path: casesDirectory).appending(path: "\(name).json")
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try slice.write(to: logFile, options: .atomic)
        guard try goldenCase.replay(powerLog: logFile) == goldenCase.expected else {
            try? fileManager.removeItem(at: logFile.deletingLastPathComponent())
            throw BookmarkReplayError.replayDiffers
        }
        try fileManager.createDirectory(at: caseFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json.write(to: caseFile, options: .atomic)
        return (goldenCase, caseFile, logFile)
    }

    static func sanitized(_ name: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-_")
        let mapped = String(name.lowercased().map { allowed.contains($0) ? $0 : "-" })
        return mapped.isEmpty ? "bookmark" : mapped
    }

    private static func bytes(of url: URL, from start: UInt64, to end: UInt64) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: start)
        return try handle.read(upToCount: Int(end - start)) ?? Data()
    }
}

// MARK: - Redaction

extension TimelineEntry {
    /// Opponents' display names are real account names: keeps only that one is known, as `Opp-P<PlayerID>`.
    public func redactingNames() -> TimelineEntry {
        var entry = self
        if var game = entry.state.game {
            for index in game.lobby.indices where game.lobby[index].displayName != nil {
                game.lobby[index].displayName = "Opp-P\(game.lobby[index].playerID)"
            }
            entry.state.game = game
        }
        return entry
    }
}

extension GameRecord {
    /// Display names become `Opp-P<PlayerID>`, as in `TimelineEntry.redactingNames()`; bookmarks are dropped.
    public func redactingNames() -> GameRecord {
        var record = self
        record.journal.displayNames = Dictionary(uniqueKeysWithValues: journal.displayNames.keys.map { ($0, "Opp-P\($0)") })
        record.bookmarks = []
        return record
    }
}
