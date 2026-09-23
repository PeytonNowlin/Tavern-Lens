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
    private let onCombatRequest: @Sendable (CombatSimulationRequest) -> Void
    private let onOddsPreview: @Sendable (OddsPreviewRequest?) -> Void
    private var follower: LogSessionFollower?

    // Guarded by `lock`: written on the follower's queue, and read by deferred flushes.
    private var engine = TavernEngine()
    private var session: LogSession?
    /// The minion pool for tribe inference; each new session's engine starts with it.
    private var pool: MinionPool?
    /// Firestone's hero stats and the card data for the hero pick; each new engine starts with them.
    private var heroStats: (stats: HeroStatsSet?, cards: CardDB?) = (nil, nil)
    /// The build catalog; each new session's engine starts with it.
    private var builds: BuildCatalog?
    private var lastPublished: LiveUpdate?
    private var lastPublishTime: ContinuousClock.Instant?
    private var pendingFlush = false
    /// Seeds of games already reported to `onGameEnded`.
    private var endedGames: Set<Int> = []
    /// How many of the engine's combat requests have been seen (dispatched, or skipped in catch-up).
    private var combatRequestsSeen = 0
    /// The odds preview last sent to `onOddsPreview`.
    private var lastOddsPreview: OddsPreviewRequest?
    private let clock = ContinuousClock()
    private let flushQueue = DispatchQueue(label: "TavernLens.LivePipeline.flush")
    private let lock = NSLock()

    /// - Parameter records: where game records are saved and resumed from; nil keeps them in memory.
    init(
        records: GameRecordStore?,
        onGameEnded: @escaping @Sendable (GameRecord) -> Void = { _ in },
        onCombatRequest: @escaping @Sendable (CombatSimulationRequest) -> Void = { _ in },
        onOddsPreview: @escaping @Sendable (OddsPreviewRequest?) -> Void = { _ in },
        publish: @escaping @Sendable (LiveUpdate) -> Void
    ) {
        self.records = records
        self.onGameEnded = onGameEnded
        self.onCombatRequest = onCombatRequest
        self.onOddsPreview = onOddsPreview
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
            engine = TavernEngine(pool: pool, builds: builds, session: newSession)
            engine.useHeroStats(heroStats.stats, cards: heroStats.cards)
            combatRequestsSeen = 0
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
        dispatchCombatRequests()
        publishIfDue()
    }

    /// Uses a new minion pool from now on, including for the game in progress.
    func usePool(_ newPool: MinionPool?) {
        lock.lock()
        defer { lock.unlock() }
        pool = newPool
        engine.usePool(newPool)
        publishIfDue()
    }

    /// The lobby's tribes read from the hero-pick banner, for the game in progress.
    func ingestScreenTribes(_ reading: ScreenTribeReading) {
        lock.lock()
        defer { lock.unlock() }
        engine.ingestScreenTribes(reading)
        publishIfDue()
    }

    /// Uses new hero stats (and card data) from now on, including for a hero pick on screen.
    func useHeroStats(_ stats: HeroStatsSet?, cards: CardDB?) {
        lock.lock()
        defer { lock.unlock() }
        heroStats = (stats, cards)
        engine.useHeroStats(stats, cards: cards)
        publishIfDue()
    }

    /// Uses a new build catalog from now on, including for the game in progress.
    func useBuilds(_ catalog: BuildCatalog?) {
        lock.lock()
        defer { lock.unlock() }
        builds = catalog
        engine.useBuilds(catalog)
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

    /// A combat that started just now goes to the simulator at once, before the state is
    /// published. One seen while catching up is already over (or can't be told apart from one
    /// that is), so it isn't simulated. Call with `lock` held.
    private func dispatchCombatRequests() {
        let requests = engine.combatRequests
        guard requests.count > combatRequestsSeen else { return }
        combatRequestsSeen = requests.count
        if !engine.isCatchingUp, let latest = requests.last { onCombatRequest(latest) }
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
        dispatchOddsPreview()
    }

    /// The recruit-phase odds preview for the state just published, when it changed: the local
    /// board now against the next opponent's last-seen board (nil outside recruit). Built with
    /// each publish, so at most about 10 times a second. Call with `lock` held.
    private func dispatchOddsPreview() {
        let preview = engine.isCatchingUp ? nil : engine.oddsPreview
        guard preview != lastOddsPreview else { return }
        lastOddsPreview = preview
        onOddsPreview(preview)
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
