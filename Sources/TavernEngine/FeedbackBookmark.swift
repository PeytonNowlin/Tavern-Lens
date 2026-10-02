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
    /// The hero-pick banner readings taken in while reading `cut` (not in the log, so a replay
    /// takes them in again at their lines); a carried-in game's earlier ones are in `resumed`.
    public var screenTribes: [LoggedScreenTribes]?

    public init(
        id: UUID = UUID(), createdAt: Date = Date(), note: String = "", cut: LogCut, powerLog: String? = nil,
        shown: TimelineEntry, resumed: GameRecord? = nil, overlay: BookmarkOverlay? = nil, advice: AdviceView? = nil,
        adviceRequest: AdvisorRequest? = nil, screenTribes: [LoggedScreenTribes]? = nil
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
        self.screenTribes = screenTribes
    }

    public var gameSeed: Int? { cut.gameSeed }
    public var bgTurn: Int? { shown.state.game?.bgTurn }
    public var phase: BGPhase? { shown.state.game?.phase }
}

extension FeedbackBookmark {
    /// A file-name-safe default name for the bookmark's golden case, e.g. `bookmark-1172082863-t6-combat-3f2a9c`.
    public var defaultCaseName: String {
        var parts = ["bookmark"]
        if let seed = gameSeed { parts.append(String(seed)) }
        if let turn = bgTurn { parts.append("t\(turn)") }
        if let phase { parts.append(phase.rawValue.lowercased()) }
        parts.append(String(id.uuidString.lowercased().prefix(6)))
        return parts.joined(separator: "-")
    }
}
