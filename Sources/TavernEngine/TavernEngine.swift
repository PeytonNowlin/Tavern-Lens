import BGIntel
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
// Combat simulation requests and their input, the tribe provider seam.
@_exported import BGIntel
// The simulator runtime, which runs the engine's combat requests.
@_exported import SimulatorRuntime

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
    /// Cards the game flagged as pool minions that the pool lacked (added for their game).
    public var poolDrift: [PoolDrift] = []
    /// The simulator input of every combat start, in order.
    public var combatRequests: [CombatSimulationRequest] = []
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
    /// An injected tribe source for the simulator, which wins over the inferred tribes.
    private let simulatorTribes: (any LobbyTribesProvider)?
    /// The simulator's tribe source when there's neither an injected one nor a pool.
    private let seenPoolTribes: SeenPoolMinionTribes
    /// The simulator input of every combat start seen, in order. Each is taken at the tag
    /// 2022 1→0 edge, when both boards are final, and appended before the line's batch is
    /// published, so a live runner can start simulating at once.
    public private(set) var combatRequests: [CombatSimulationRequest] = []
    private var combatStartsSeen = 0
    /// Each opponent's side of the latest combat-start input against them, by PlayerID, for the
    /// recruit-phase odds preview. Reset with each new game.
    private var lastSeenSides: [Int: (seed: Int?, bgTurn: Int, side: BattleBoard)] = [:]
    private let sessionName: String?
    private var clock: LogClock?
    /// Suppresses publishing while the existing log is replayed.
    public private(set) var isCatchingUp = false
    /// Dates and sessions of each game in `history.games`, by the same index.
    private var recordInfo: [RecordInfo] = []
    /// Games with checkpoints not yet handed out by `takeUnsavedRecords()`.
    private var unsaved: Set<Int> = []
    /// Where reading started: the entry point's line and byte offset (line 1 at byte 0
    /// unless `start(at:)` or `skipLines(_:)` said otherwise; the offset is nil after `skipLines`).
    public private(set) var startLine = 1
    public private(set) var startByteOffset: UInt64? = 0
    /// The in-progress record carried in with `resume(_:)`, as it was then, when it was accepted.
    public private(set) var resumedRecord: GameRecord?
    /// The minion pool and the lobby's tribes (nothing without a pool).
    private var tribes: TribeTracker
    /// The local player's hero-pick offer, and the stats it's joined with (none without stats).
    private var heroPick = BGHeroPickTracker()
    private var heroPickData: HeroPickData?
    /// Build detection, shop highlights and opponents' likely builds (nothing without a catalog).
    private var builds: BuildTracker

    private struct RecordInfo: Sendable {
        var sessions: [String] = []
        var startedAt: Date?
        var endedAt: Date?
        var updatedAt: Date?
        var reconnects = 0
        var bookmarks: [FeedbackBookmark] = []
    }

    /// - Parameters:
    ///   - cards: card data for resolving card IDs to names; nil leaves names out.
    ///   - pool: the live minion pool, for inferring the lobby's tribes; nil leaves tribes out.
    ///   - builds: the build catalog, for detecting builds and highlighting the shop; nil leaves builds out.
    ///   - session: the session folder the Power.log is from. It dates the game records
    ///     (the logs only carry times of day); nil leaves records undated.
    ///   - simulatorTribes: the lobby's tribes for the combat simulator. nil uses the tribe
    ///     inference's answer when there's a pool, else the tribes of the single-tribe pool
    ///     minions seen so far (`SeenPoolMinionTribes`, which needs `cards`).
    public init(
        cards: CardDB? = nil, pool: MinionPool? = nil, builds: BuildCatalog? = nil, session: LogSession? = nil,
        timeZone: TimeZone = .current, simulatorTribes: (any LobbyTribesProvider)? = nil
    ) {
        self.cards = cards
        tribes = TribeTracker(pool: pool)
        self.builds = BuildTracker(catalog: builds)
        self.simulatorTribes = simulatorTribes
        seenPoolTribes = SeenPoolMinionTribes(cards: cards)
        sessionName = session?.name
        clock = session.map { LogClock(session: $0, timeZone: timeZone) }
    }

    public var games: [BGGameRecord] { history.games }

    public var diagnostics: EngineDiagnostics {
        EngineDiagnostics(linesRead: linesRead, parse: parser.diagnostics, store: store.diagnostics)
    }

    public var result: ReplayResult {
        ReplayResult(
            timeline: timeline, games: games, diagnostics: diagnostics, records: records, poolDrift: tribes.drift,
            combatRequests: combatRequests
        )
    }

    // MARK: - Pool and tribes

    /// Cards the game flagged as pool minions that the pool lacked; each was added for its game.
    public var poolDrift: [PoolDrift] { tribes.drift }

    /// The current game's tribe inference; nil without a pool or a game.
    public var tribeEstimate: TribeEstimate? { tribes.estimate }

    /// Sets (or replaces) the minion pool, such as when card data finishes loading after a
    /// game started. The current game's evidence so far is weighed again with it.
    public mutating func usePool(_ pool: MinionPool?) {
        tribes.usePool(pool)
        if !isCatchingUp, timeline.last != nil { publish() }
    }

    /// The lobby's tribes read from the hero-pick banner: the strongest tribe evidence, which
    /// the log's own evidence cross-checks. Ignored outside a solo Battlegrounds game.
    public mutating func ingestScreenTribes(_ reading: ScreenTribeReading) {
        tribes.add(reading)
        if !isCatchingUp { publish() }
    }

    /// Sets (or replaces) Firestone's hero stats for the hero pick; nil leaves the hero pick out
    /// of the view. `cards` maps skins to their base hero and names the heroes when the
    /// engine has no card data of its own.
    public mutating func useHeroStats(_ stats: HeroStatsSet?, cards: CardDB? = nil) {
        heroPickData = stats.map { HeroPickData(stats: $0, cards: cards) }
        if !isCatchingUp, timeline.last != nil { publish() }
    }

    /// Sets (or replaces) the build catalog, such as when the build data finishes loading.
    /// Detection starts over with it.
    public mutating func useBuilds(_ catalog: BuildCatalog?) {
        builds.use(catalog)
        if !isCatchingUp, timeline.last != nil { publish() }
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
            startedAt: info.startedAt, endedAt: info.endedAt, updatedAt: info.updatedAt, bookmarks: info.bookmarks
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
            updatedAt: record.updatedAt, reconnects: record.summary.reconnects.count, bookmarks: record.bookmarks
        ))
        var carried = record
        carried.bookmarks = []
        resumedRecord = carried
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
        startLine = count + 1
        startByteOffset = count == 0 ? 0 : nil
    }

    /// Reading starts at the entry point (`PowerLogEntryPoint`): line numbers count from
    /// its line, and bookmarks record its byte offset. Call before ingesting any line.
    public mutating func start(at entry: PowerLogEntryPoint) {
        skipLines(entry.line - 1)
        startByteOffset = entry.byteOffset
    }

    // MARK: - Bookmarks

    /// The moment on screen as a bookmark: the published state and the line it was
    /// published at, the game's seed, where reading started and the record carried in.
    /// Nil while catching up or before a game has been shown. The byte offset of the
    /// last line isn't known here; `LogCut.locating(in:)` fills it in from the log.
    public func bookmark(note: String = "", id: UUID = UUID(), createdAt: Date = Date()) -> FeedbackBookmark? {
        guard !isCatchingUp, let shown = timeline.last, shown.state.game != nil, let index = history.currentIndex
        else { return nil }
        let cut = LogCut(
            session: sessionName, gameSeed: history.games[index].gameSeed, startLine: startLine,
            startByteOffset: startByteOffset, endLine: shown.position.line
        )
        return FeedbackBookmark(id: id, createdAt: createdAt, note: note, cut: cut, shown: shown, resumed: resumedRecord)
    }

    /// Stores a bookmark in its game's record (by seed; the current game when unseeded),
    /// replacing one with the same ID, and queues the record for saving. False when the
    /// game isn't one this engine knows.
    @discardableResult
    public mutating func addBookmark(_ bookmark: FeedbackBookmark) -> Bool {
        let index: Int? = if let seed = bookmark.gameSeed {
            history.games.indices.last { history.games[$0].gameSeed == seed }
        } else {
            history.currentIndex
        }
        guard let index else { return false }
        while recordInfo.count <= index { recordInfo.append(RecordInfo()) }
        recordInfo[index].bookmarks.removeAll { $0.id == bookmark.id }
        recordInfo[index].bookmarks.append(bookmark)
        recordInfo[index].bookmarks.sort { $0.createdAt < $1.createdAt }
        unsaved.insert(index)
        return true
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
        let clock = clock
        for event in batch {
            var changes: [EntityChange] = []
            store.apply(event, changes: { changes.append($0) })
            for change in changes {
                history.observe(change, in: store, at: position)
                tribes.observe(change, in: store, history: history, date: { clock?.currentDate })
                if history.combatStartCount != combatStartsSeen { noteCombatStart(at: position) }
            }
            history.observe(event, in: store)
            tribes.observe(event)
            heroPick.observe(event)
            if event == .taskListEnd {
                tribes.taskListEnded(store, at: position)
                if !isCatchingUp { publish() }
            }
        }
        if !history.changedGames.isEmpty { noteChangedGames() }
    }

    /// A combat just started (history accepted the tag 2022 1→0 edge): builds the simulator's input
    /// from the store as it is at this line, before any Start of Combat effect.
    private mutating func noteCombatStart(at position: LogPosition) {
        combatStartsSeen = history.combatStartCount
        guard let snapshot = BGSnapshot.project(store), let opponent = snapshot.combatOpponentPlayerID,
              let input = BattleInputBuilder.build(
                  store: store, snapshot: snapshot, validTribes: simulatorLobbyTribes(snapshot)
              )
        else { return }
        combatRequests.append(CombatSimulationRequest(
            gameSeed: snapshot.gameSeed, bgTurn: snapshot.bgTurn, opponentPlayerID: opponent, position: position,
            input: input
        ))
        if lastSeenSides.values.contains(where: { $0.seed != snapshot.gameSeed }) { lastSeenSides = [:] }
        lastSeenSides[opponent] = (snapshot.gameSeed, snapshot.bgTurn, input.opponentBoard)
    }

    /// The recruit-phase odds preview as of now: the local player's current board, hero and
    /// mechanics against the next opponent's last-seen board (without data when they haven't been
    /// seen). Nil outside the recruit phase or without a next opponent. Built on demand from the
    /// store, so a live caller asks for it when the state it shows changes.
    ///
    /// The opponent's side is their side of the combat-start input when they were last fought;
    /// for a game carried in from an earlier log it's rebuilt from the history's last-seen board.
    public var oddsPreview: OddsPreviewRequest? {
        guard let snapshot = BGSnapshot.project(store), snapshot.phase == .recruit,
              let next = snapshot.nextOpponentPlayerID
        else { return nil }
        var opponent: (side: BattleBoard, seenTurn: Int, source: OddsPreviewRequest.OpponentSource)?
        if let seen = history.lobby.lastSeenBoards[next] {
            if let captured = lastSeenSides[next], captured.seed == snapshot.gameSeed, captured.bgTurn == seen.bgTurn {
                opponent = (captured.side, seen.bgTurn, .combatStart)
            } else if let hero = snapshot.lobby.first(where: { $0.playerID == next })?.hero,
                      let side = BattleInputBuilder.side(
                          seen: seen, heroCardID: hero.cardID, heroEntityID: hero.entityID, hpLeft: hero.hp, tier: hero.tier ?? 1
                      ) {
                opponent = (side, seen.bgTurn, .lastSeenBoard)
            }
        }
        return BattleInputBuilder.preview(
            store: store, snapshot: snapshot, opponent: opponent, validTribes: simulatorLobbyTribes(snapshot)
        )
    }

    /// The advisor's view of the recruit phase now: the odds preview's combat plus the gold, board,
    /// hand, shop and tavern buttons the candidate actions are built from. Nil outside the recruit
    /// phase or without a next opponent; without data (and so without candidates) when that
    /// opponent hasn't been seen. Built on demand from the store, like `oddsPreview`.
    public var advisorRequest: AdvisorRequest? {
        guard let preview = oddsPreview, let snapshot = BGSnapshot.project(store) else { return nil }
        return BattleInputBuilder.advisorRequest(store: store, snapshot: snapshot, preview: preview)
    }

    /// The lobby's tribes for the simulator: the injected source's, else the tribe inference's
    /// confirmed and likely tribes (while there's a pool), else the seen pool minions' tribes.
    private func simulatorLobbyTribes(_ snapshot: BGSnapshot) -> Set<HS.Race>? {
        if let simulatorTribes { return simulatorTribes.lobbyTribes(store: store, snapshot: snapshot) }
        if tribes.hasResolver { return tribes.simulatorLobby }
        return seenPoolTribes.lobbyTribes(store: store, snapshot: snapshot)
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
        let snapshot = BGSnapshot.project(store)
        var next = Self.viewState(
            snapshot: snapshot, record: history.current, lobby: history.lobby, cards: cards,
            tribes: tribes.view(bgTurn: snapshot?.bgTurn ?? 0)
        )
        if next.game?.phase == .heroPick, let data = heroPickData, let pick = heroPick.project(store, lastTaskListEnded: parser.lastTaskListEnded) {
            let pool = tribes.basePool
            next.game?.heroPick = HeroPickView(
                pick, data: data, cards: cards, tribes: tribes.estimate, heroRules: pool.map { pool in pool.heroRule },
                now: clock?.currentDate
            )
        }
        if var game = next.game {
            builds.apply(to: &game, gameIndex: history.currentIndex)
            next.game = game
        }
        guard next != state else { return }
        state = next
        timeline.append(TimelineEntry(position: LogPosition(line: linesRead, time: String(lastTimestamp)), state: next))
    }

    static func viewState(
        snapshot: BGSnapshot?, record: BGGameRecord?, lobby: BGLobbyMemory, cards: CardDB?, tribes: TribesView? = nil
    ) -> ViewState {
        guard let snapshot, let record else { return .noGame }
        var game = GameView(snapshot, record: record, lobby: lobby, cards: cards)
        game.tribes = tribes
        return ViewState(status: record.end == nil ? .inGame : .gameOver, game: game)
    }
}

extension TavernEngine {
    /// Replays lines from memory.
    public static func replay(
        lines: some Sequence<String>, cards: CardDB? = nil, pool: MinionPool? = nil, builds: BuildCatalog? = nil
    ) -> ReplayResult {
        var engine = TavernEngine(cards: cards, pool: pool, builds: builds)
        for line in lines { engine.ingest(line) }
        engine.finish()
        return engine.replayResult
    }

    /// Replays a recorded Power.log from disk. With `session`, the records are dated.
    public static func replay(
        fileAt url: URL, cards: CardDB? = nil, pool: MinionPool? = nil, builds: BuildCatalog? = nil,
        session: LogSession? = nil, timeZone: TimeZone = .current
    ) throws -> ReplayResult {
        var engine = TavernEngine(cards: cards, pool: pool, builds: builds, session: session, timeZone: timeZone)
        try LogFileReader.forEachLine(in: url) { engine.ingest($0) }
        engine.finish()
        return engine.replayResult
    }

    var replayResult: ReplayResult {
        var result = result
        result.entities = entityRows
        return result
    }
}
