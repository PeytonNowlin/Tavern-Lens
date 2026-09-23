import BGState
import EntityStore
import Foundation
import HSLog
import PowerParser

@_exported import struct BGState.BGGameRecord
@_exported import struct PowerParser.LogPosition

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

    public init() {}

    public var games: [BGGameRecord] { history.games }

    public var diagnostics: EngineDiagnostics {
        EngineDiagnostics(linesRead: linesRead, parse: parser.diagnostics, store: store.diagnostics)
    }

    public var result: ReplayResult {
        ReplayResult(timeline: timeline, games: games, diagnostics: diagnostics)
    }

    /// Ingests one log line (without its newline).
    public mutating func ingest(_ rawLine: String) {
        linesRead += 1
        var events: [PowerEvent] = []
        if let line = parser.feed(rawLine, emit: { events.append($0) }) {
            lastTimestamp = line.timestamp
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
            if event == .taskListEnd {
                publish()
            }
        }
    }

    private mutating func publish() {
        history.refresh(from: store)
        let next = Self.viewState(snapshot: BGSnapshot.project(store), record: history.current)
        guard next != state else { return }
        state = next
        timeline.append(TimelineEntry(position: LogPosition(line: linesRead, time: String(lastTimestamp)), state: next))
    }

    static func viewState(snapshot: BGSnapshot?, record: BGGameRecord?) -> ViewState {
        guard let snapshot, let record else { return .noGame }
        let game = GameView(
            gameType: snapshot.gameType,
            localPlayerID: snapshot.localPlayerID,
            localHeroCardID: snapshot.localHero?.cardID,
            bgTurn: snapshot.bgTurn
        )
        return ViewState(status: record.end == nil ? .inGame : .gameOver, game: game)
    }
}

extension TavernEngine {
    /// Replays lines from memory.
    public static func replay(lines: some Sequence<String>) -> ReplayResult {
        var engine = TavernEngine()
        for line in lines { engine.ingest(line) }
        engine.finish()
        return engine.result
    }

    /// Replays a recorded Power.log from disk.
    public static func replay(fileAt url: URL) throws -> ReplayResult {
        var engine = TavernEngine()
        try LogFileReader.forEachLine(in: url) { engine.ingest($0) }
        engine.finish()
        return engine.result
    }
}
