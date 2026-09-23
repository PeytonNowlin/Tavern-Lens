import Foundation
import HSLog
import TavernEngine

/// What the live pipeline reports to the main actor.
struct LiveUpdate: Sendable {
    var session: LogSession?
    var state: ViewState
    var scene: String?
}

/// Log lines in, view states out, off the main thread.
///
/// A `LogSessionFollower` delivers lines in order on its own serial queue, and this
/// feeds them straight into a `TavernEngine` there, so reading, parsing and
/// reducing stay strictly ordered. Each new session (a client launch) gets a fresh
/// engine. Updates reach `publish` only when something changed, at most about
/// 10 times a second.
///
/// Joining a session catches up silently: Power.log is read from its latest game
/// (`PowerLogEntryPoint`) with publishing suppressed, and the state it arrives at is
/// published once. A game still in progress carries over into the next session's
/// engine (the client restarted mid-game), or comes from the saved records when the
/// app itself restarted, so a reconnect keeps its history. Game records are saved as
/// they reach checkpoints, and `onGameEnded` is told once per game that ends (log
/// housekeeping runs then).
final class LivePipeline: @unchecked Sendable {
    static let minimumPublishInterval: Duration = .milliseconds(100)

    private let publish: @Sendable (LiveUpdate) -> Void
    private let records: GameRecordStore?
    private let onGameEnded: @Sendable (GameRecord) -> Void
    private var follower: LogSessionFollower?

    // Guarded by `lock`: written on the follower's queue, and read by deferred flushes.
    private var engine = TavernEngine()
    private var session: LogSession?
    private var lastPublished: LiveUpdate?
    private var lastPublishTime: ContinuousClock.Instant?
    private var pendingFlush = false
    /// Seeds of games already reported to `onGameEnded`.
    private var endedGames: Set<Int> = []
    private let clock = ContinuousClock()
    private let flushQueue = DispatchQueue(label: "TavernLens.LivePipeline.flush")
    private let lock = NSLock()

    /// - Parameter records: where game records are saved and resumed from; nil keeps them in memory.
    init(
        records: GameRecordStore?,
        onGameEnded: @escaping @Sendable (GameRecord) -> Void = { _ in },
        publish: @escaping @Sendable (LiveUpdate) -> Void
    ) {
        self.records = records
        self.onGameEnded = onGameEnded
        self.publish = publish
    }

    func start(logsDirectory: URL, launchDate: Date?) {
        let follower = LogSessionFollower(
            logsDirectory: logsDirectory, launchDate: launchDate, startsAtLatestGame: true
        ) { [weak self] event in
            self?.handle(event)
        }
        self.follower = follower
        follower.start()
    }

    func stop() {
        follower?.stop()
        follower = nil
        lock.lock()
        defer { lock.unlock() }
        saveRecords()
    }

    private func handle(_ event: LogSessionFollower.Event) {
        lock.lock()
        defer { lock.unlock() }
        switch event {
        case .sessionStarted(let newSession):
            saveRecords()
            // A game the previous session left unfinished may be resumed in this one.
            let carried = engine.inProgressRecord ?? records?.latestInProgress()
            session = newSession
            engine = TavernEngine(session: newSession)
            if let carried { engine.resume(carried) }
            engine.beginCatchUp()
        case .powerLogEntry(let entry):
            engine.start(at: entry)
        case .caughtUp(let file):
            if file == LogFileName.power { engine.endCatchUp() }
        case .lines(let file, let lines):
            switch file {
            case LogFileName.power:
                for line in lines { engine.ingest(line) }
            case LogFileName.loadingScreen:
                for line in lines { engine.ingestLoadingScreen(line) }
            default:
                break
            }
        }
        if !engine.isCatchingUp { saveRecords() }
        publishIfDue()
    }

    // MARK: - Bookmarks

    /// The moment the engine last published, as a bookmark with no note yet: its state,
    /// the game's seed, and the Power.log stretch (entry point to the published line, with
    /// byte offsets) that replays to it. Nil while catching up or with no game shown.
    func captureBookmark(createdAt: Date = Date()) -> FeedbackBookmark? {
        lock.lock()
        let captured = engine.bookmark(createdAt: createdAt)
        let powerLog = session?.powerLog
        lock.unlock()
        guard var bookmark = captured else { return nil }
        if let powerLog {
            bookmark.powerLog = powerLog.path(percentEncoded: false)
            // Lines already read never move (the log only grows), so this can run outside the lock.
            bookmark.cut = bookmark.cut.locating(in: powerLog)
        }
        return bookmark
    }

    /// Stores a bookmark in its game's record and saves it. False when neither the engine
    /// nor the record store knows its game.
    @discardableResult
    func save(_ bookmark: FeedbackBookmark) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if engine.addBookmark(bookmark) {
            saveRecords()
            return true
        }
        // The session changed while the note was typed: the game is on disk, if anywhere.
        return (try? records?.add(bookmark)) == true
    }

    /// Call with `lock` held.
    private func saveRecords() {
        for record in engine.takeUnsavedRecords() {
            try? records?.save(record)
            if record.outcome != .inProgress, let seed = record.gameSeed, endedGames.insert(seed).inserted {
                onGameEnded(record)
            }
        }
    }

    /// Call with `lock` held.
    private func publishIfDue() {
        let update = LiveUpdate(session: session, state: engine.state, scene: engine.scene)
        guard !isPublished(update) else { return }
        let now = clock.now
        if let last = lastPublishTime, now - last < Self.minimumPublishInterval {
            guard !pendingFlush else { return }
            pendingFlush = true
            let delay = Self.minimumPublishInterval - (now - last)
            flushQueue.asyncAfter(deadline: .now() + delay.timeInterval) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                defer { self.lock.unlock() }
                self.pendingFlush = false
                self.publishIfDue()
            }
            return
        }
        lastPublished = update
        lastPublishTime = now
        publish(update)
    }

    private func isPublished(_ update: LiveUpdate) -> Bool {
        guard let lastPublished else { return false }
        return lastPublished.session == update.session && lastPublished.state == update.state
            && lastPublished.scene == update.scene
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
