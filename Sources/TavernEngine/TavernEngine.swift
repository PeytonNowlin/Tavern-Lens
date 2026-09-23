import BGState
import EntityStore
import Foundation
import HSLog
import PowerParser

@_exported import struct BGState.BGGameRecord
@_exported import enum BGState.BGPhase
@_exported import enum BGState.BGCardKind
@_exported import enum BGState.BGKeyword
@_exported import enum BGState.BGPlacementSource
@_exported import struct PowerParser.LogPosition
// Card data is an engine input (`TavernEngine(cards:)`), and the app loads it.
@_exported import HSData

/// Counts of input the engine tolerated rather than understood.
public struct EngineDiagnostics: Codable, Hashable, Sendable {
    public var linesRead: Int
    public var parse: ParseDiagnostics
    public var store: StoreDiagnostics
}

/// Everything a replay produced.
public struct ReplayResult: Sendable {
    public var timeline: [TimelineEntry]
    public var games: [BGGameRecord]
    public var diagnostics: EngineDiagnostics
    /// The last game's entities at end of input, for the debug window. Filled by `replay`.
    public var entities: [EntityRow] = []
    /// The full record of each game in `games`, as it would be saved.
    public var records: [GameRecord] = []
}

/// The headless composition root.
///
/// Feed it Power.log lines in order; it emits a timeline of `ViewState`s and a list
/// of game records. A new timeline entry is appended only when the view state
/// changes, and only at a task-list boundary (`PowerProcessor.EndCurrentTaskList`)
/// or at end of input, so multi-line updates settle before they're shown.
///
/// Live tailing and replay use the same entry points: `ingest(_:)` per line, then
/// `finish()` when the input ends (replay only).
///
/// Joining a game late (the app started mid-game) is a catch-up: `beginCatchUp()`, the
/// log's existing lines, then `endCatchUp()`. In between, the state is reduced as usual
/// but nothing is published; the end publishes one state. Game records come out as they
/// reach checkpoints (`takeUnsavedRecords()`), dated from the session folder.
public struct TavernEngine: Sendable {
    public private(set) var timeline: [TimelineEntry] = []
    public private(set) var state: ViewState = .noGame
    public private(set) var linesRead = 0
    /// The client's current scene from LoadingScreen.log (e.g. `BACON`, `GAMEPLAY`), if seen.
    public private(set) var scene: String?

    private var parser = PowerLogParser()
    private var store = EntityStore()
    private var history = BGGameHistory()
    private var lastTimestamp: Substring = ""
    private let cards: CardDB?
    private let sessionName: String?
    private var clock: LogClock?
    /// Suppresses publishing while the existing log is replayed.
    public private(set) var isCatchingUp = false
    /// Dates and sessions of each game in `history.games`, by the same index.
    private var recordInfo: [RecordInfo] = []
    /// Games with checkpoints not yet handed out by `takeUnsavedRecords()`.
    private var unsaved: Set<Int> = []

    private struct RecordInfo: Sendable {
        var sessions: [String] = []
        var startedAt: Date?
        var endedAt: Date?
        var updatedAt: Date?
        var reconnects = 0
    }

    /// - Parameters:
    ///   - cards: card data for resolving card IDs to names; nil leaves names out.
    ///   - session: the session folder the Power.log is from. It dates the game records
    ///     (the logs only carry times of day); nil leaves records undated.
    public init(cards: CardDB? = nil, session: LogSession? = nil, timeZone: TimeZone = .current) {
        self.cards = cards
        sessionName = session?.name
        clock = session.map { LogClock(session: $0, timeZone: timeZone) }
    }

    public var games: [BGGameRecord] { history.games }

    public var diagnostics: EngineDiagnostics {
        EngineDiagnostics(linesRead: linesRead, parse: parser.diagnostics, store: store.diagnostics)
    }

    public var result: ReplayResult {
        ReplayResult(timeline: timeline, games: games, diagnostics: diagnostics, records: records)
    }

    /// Every game's full record.
    public var records: [GameRecord] { history.games.indices.map(record(at:)) }

    /// The game still in progress, if any: what a client restart may resume.
    public var inProgressRecord: GameRecord? {
        history.games.indices.last { history.games[$0].outcome == .inProgress }.map(record(at:))
    }

    /// The records that reached a checkpoint since the last call, for saving.
    public mutating func takeUnsavedRecords() -> [GameRecord] {
        let indices = unsaved.sorted()
        unsaved = []
        return indices.map(record(at:))
    }

    private func record(at index: Int) -> GameRecord {
        let info = index < recordInfo.count ? recordInfo[index] : RecordInfo()
        return GameRecord(
            summary: history.games[index], journal: history.journals[index], sessions: info.sessions,
            startedAt: info.startedAt, endedAt: info.endedAt, updatedAt: info.updatedAt
        )
    }

    /// Carries in a game in progress from an earlier log (the client restarted mid-game,
    /// or the app did): if this log resumes it (a `CREATE_GAME` with its seed), its
    /// history, such as the opponent boards already seen, carries on; if it starts a
    /// different game, the carried one is abandoned. Ignored unless the record is in
    /// progress and its game isn't known yet.
    public mutating func resume(_ record: GameRecord) {
        let count = history.games.count
        history.resume(record.summary, journal: record.journal)
        guard history.games.count > count, let seed = record.gameSeed else { return }
        while recordInfo.count < count { recordInfo.append(RecordInfo()) }
        recordInfo.append(RecordInfo(
            sessions: record.sessions, startedAt: record.startedAt, endedAt: record.endedAt,
            updatedAt: record.updatedAt, reconnects: record.summary.reconnects.count
        ))
        var metadata = GameMetadata()
        metadata.gameType = record.summary.gameType
        metadata.buildNumber = record.summary.buildNumber
        store.rememberGame(seed: seed, metadata: metadata)
    }

    /// The lines before the entry point were skipped (`PowerLogEntryPoint`), so line
    /// numbers count from there. Call before ingesting any line.
    public mutating func skipLines(_ count: Int) {
        precondition(linesRead == 0, "skipLines must come before the first line")
        linesRead = count
    }

    /// From here until `endCatchUp()`, lines are reduced but no state is published.
    public mutating func beginCatchUp() {
        isCatchingUp = true
    }

    /// Publishes the state the catch-up arrived at and goes live.
    public mutating func endCatchUp() {
        guard isCatchingUp else { return }
        isCatchingUp = false
        publish()
    }

    /// The current game's entities, by entity ID, with card and tag names resolved.
    public var entityRows: [EntityRow] {
        store.entities.values.sorted { $0.id < $1.id }.map { EntityRow($0, cards: cards) }
    }

    /// Ingests one log line (without its newline).
    public mutating func ingest(_ rawLine: String) {
        linesRead += 1
        var events: [PowerEvent] = []
        if let line = parser.feed(rawLine, emit: { events.append($0) }) {
            lastTimestamp = line.timestamp
            clock?.observe(line.timestamp)
        }
        process(events)
    }

    /// Ingests one LoadingScreen.log line (without its newline).
    ///
    /// Scene changes don't affect the view state; they're kept for status display.
    public mutating func ingestLoadingScreen(_ rawLine: String) {
        if case .sceneLoaded(_, let current) = LoadingScreenEvent(line: rawLine) {
            scene = current
        }
    }

    /// Ends the input: flushes a trailing header and publishes the final state.
    public mutating func finish() {
        var events: [PowerEvent] = []
        parser.finish(emit: { events.append($0) })
        process(events)
        isCatchingUp = false
        publish()
    }

    private mutating func process(_ batch: [PowerEvent]) {
        guard !batch.isEmpty else { return }
        let position = LogPosition(line: linesRead, time: String(lastTimestamp))
        for event in batch {
            var changes: [EntityChange] = []
            store.apply(event, changes: { changes.append($0) })
            for change in changes {
                history.observe(change, in: store, at: position)
            }
            history.observe(event, in: store)
            if event == .taskListEnd, !isCatchingUp {
                publish()
            }
        }
        if !history.changedGames.isEmpty { noteChangedGames() }
    }

    /// Dates the games that reached a checkpoint and queues them for saving.
    private mutating func noteChangedGames() {
        let now = clock?.currentDate
        for index in history.changedGames {
            while recordInfo.count <= index { recordInfo.append(RecordInfo()) }
            let game = history.games[index]
            var info = recordInfo[index]
            if info.startedAt == nil, info.sessions.isEmpty { info.startedAt = now }
            if let sessionName, game.reconnects.count > info.reconnects || info.sessions.isEmpty,
               info.sessions.last != sessionName {
                info.sessions.append(sessionName)
            }
            info.reconnects = game.reconnects.count
            if game.end != nil, info.endedAt == nil { info.endedAt = now }
            if index == history.currentIndex || info.updatedAt == nil { info.updatedAt = now }
            recordInfo[index] = info
            unsaved.insert(index)
        }
        history.clearChangedGames()
    }

    private mutating func publish() {
        history.refresh(from: store)
        let next = Self.viewState(
            snapshot: BGSnapshot.project(store), record: history.current, lobby: history.lobby, cards: cards
        )
        guard next != state else { return }
        state = next
        timeline.append(TimelineEntry(position: LogPosition(line: linesRead, time: String(lastTimestamp)), state: next))
    }

    static func viewState(snapshot: BGSnapshot?, record: BGGameRecord?, lobby: BGLobbyMemory, cards: CardDB?) -> ViewState {
        guard let snapshot, let record else { return .noGame }
        return ViewState(
            status: record.end == nil ? .inGame : .gameOver,
            game: GameView(snapshot, record: record, lobby: lobby, cards: cards)
        )
    }
}

extension TavernEngine {
    /// Replays lines from memory.
    public static func replay(lines: some Sequence<String>, cards: CardDB? = nil) -> ReplayResult {
        var engine = TavernEngine(cards: cards)
        for line in lines { engine.ingest(line) }
        engine.finish()
        return engine.replayResult
    }

    /// Replays a recorded Power.log from disk. With `session`, the records are dated.
    public static func replay(fileAt url: URL, cards: CardDB? = nil, session: LogSession? = nil) throws -> ReplayResult {
        var engine = TavernEngine(cards: cards, session: session)
        try LogFileReader.forEachLine(in: url) { engine.ingest($0) }
        engine.finish()
        return engine.replayResult
    }

    private var replayResult: ReplayResult {
        var result = result
        result.entities = entityRows
        return result
    }
}
