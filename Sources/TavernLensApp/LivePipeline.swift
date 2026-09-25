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
///
/// Nothing here blocks the main thread: the data updates (`usePool`, `useBuilds`,
/// `useHeroStats`), saving a bookmark and stopping run on a control queue, and a bookmark is
/// captured from a snapshot of the last published moment, kept under a lock of its own, so
/// the hotkey never waits for a batch of lines or for disk I/O.
final class LivePipeline: @unchecked Sendable {
    static let minimumPublishInterval: Duration = .milliseconds(100)

    private let publish: @Sendable (LiveUpdate) -> Void
    private let records: GameRecordStore?
    private let onGameEnded: @Sendable (GameRecord) -> Void
    private let onCombatRequest: @Sendable (CombatSimulationRequest) -> Void
    private let onOddsPreview: @Sendable (OddsPreviewRequest?) -> Void
    private let onAdvisorRequest: @Sendable (AdvisorRequest?) -> Void
    private var follower: LogSessionFollower?

    // Guarded by `lock`: written on the follower's queue, and read by deferred flushes.
    private var engine = TavernEngine()
    private var session: LogSession?
    /// The pool, builds and hero stats each new session's engine starts with (`TavernEngine(setup:)`).
    private var setup = EngineSetup()
    private var lastPublished: LiveUpdate?
    private var lastPublishTime: ContinuousClock.Instant?
    private var pendingFlush = false
    /// Seeds of games already reported to `onGameEnded`.
    private var endedGames: Set<Int> = []
    /// How many of the engine's combat requests have been seen (dispatched, or skipped in catch-up).
    private var combatRequestsSeen = 0
    /// The odds preview last sent to `onOddsPreview`.
    private var lastOddsPreview: OddsPreviewRequest?
    /// The advisor request last sent to `onAdvisorRequest`.
    private var lastAdvisorRequest: AdvisorRequest?
    private let clock = ContinuousClock()
    private let flushQueue = DispatchQueue(label: "TavernLens.LivePipeline.flush")
    /// Data updates, bookmark saves and stopping, off the main thread and in order.
    private let controlQueue = DispatchQueue(label: "TavernLens.LivePipeline.control", qos: .userInitiated)
    private let lock = NSLock()
    /// The moment a bookmark would capture: the engine's last publish, as a bookmark with no
    /// note, ID or time yet. Guarded by `momentLock` (held only to copy it).
    private var moment: FeedbackBookmark?
    private var momentTimelineCount = -1
    private let momentLock = NSLock()

    /// - Parameter records: where game records are saved and resumed from; nil keeps them in memory.
    init(
        records: GameRecordStore?,
        onGameEnded: @escaping @Sendable (GameRecord) -> Void = { _ in },
        onCombatRequest: @escaping @Sendable (CombatSimulationRequest) -> Void = { _ in },
        onOddsPreview: @escaping @Sendable (OddsPreviewRequest?) -> Void = { _ in },
        onAdvisorRequest: @escaping @Sendable (AdvisorRequest?) -> Void = { _ in },
        publish: @escaping @Sendable (LiveUpdate) -> Void
    ) {
        self.records = records
        self.onGameEnded = onGameEnded
        self.onCombatRequest = onCombatRequest
        self.onOddsPreview = onOddsPreview
        self.onAdvisorRequest = onAdvisorRequest
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

    /// Stops following; the records still unsaved are saved on the control queue.
    func stop() {
        follower?.stop()
        follower = nil
        controlQueue.async { [self] in
            lock.withLock { saveRecords() }
        }
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
            engine = TavernEngine(setup: setup, session: newSession)
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
        noteMoment()
    }

    /// Uses a new minion pool from now on, including for the game in progress.
    func usePool(_ newPool: MinionPool?) {
        updateEngine {
            $0.setup.pool = newPool
            $0.engine.usePool(newPool)
        }
    }

    /// The lobby's tribes read from the hero-pick banner, for the game in progress.
    func ingestScreenTribes(_ reading: ScreenTribeReading) {
        updateEngine { $0.engine.ingestScreenTribes(reading) }
    }

    /// Updates population priors for an active or future trinket offer.
    func useTrinketStats(_ stats: TrinketStats?) {
        updateEngine {
            $0.setup.trinketStats = stats
            $0.engine.useTrinketStats(stats)
        }
    }

    /// Uses new hero stats (and card data), including for a hero pick on screen.
    func useHeroStats(_ stats: HeroStatsSet?, cards: CardDB?) {
        updateEngine {
            $0.setup.heroStats = stats
            $0.setup.heroCards = cards
            $0.engine.useHeroStats(stats, cards: cards)
        }
    }

    /// Uses a new build catalog from now on, including for the game in progress.
    func useBuilds(_ catalog: BuildCatalog?) {
        updateEngine {
            $0.setup.builds = catalog
            $0.engine.useBuilds(catalog)
        }
    }

    /// Changes the engine on the control queue, then publishes and saves what changed.
    private func updateEngine(_ change: @escaping @Sendable (LivePipeline) -> Void) {
        controlQueue.async { [self] in
            lock.withLock {
                change(self)
                if !engine.isCatchingUp { saveRecords() }
                publishIfDue()
                // A screen reading may change the moment without a new publish.
                momentTimelineCount = -2
                noteMoment()
            }
        }
    }

    // MARK: - Bookmarks

    /// The moment the engine last published, as a bookmark with no note yet: its state, the
    /// game's seed, the Power.log stretch (entry point to the published line) that replays to
    /// it, and the screen readings taken in along the way. Nil while catching up or with no
    /// game shown. Instant: a copy of the snapshot taken at the last publish; the stretch's
    /// byte offsets are found when it's saved (`save`).
    func captureBookmark(createdAt: Date = Date()) -> FeedbackBookmark? {
        guard var bookmark = momentLock.withLock({ moment }) else { return nil }
        bookmark.id = UUID()
        // Whole seconds, as `FeedbackBookmark.init` keeps them.
        bookmark.createdAt = Date(timeIntervalSinceReferenceDate: createdAt.timeIntervalSinceReferenceDate.rounded(.down))
        return bookmark
    }

    /// Keeps the capturable moment current. Call with `lock` held.
    private func noteMoment() {
        let count = engine.isCatchingUp ? -1 : engine.timeline.count
        guard count != momentTimelineCount || engine.isCatchingUp else { return }
        var bookmark = engine.bookmark()
        if var captured = bookmark, let powerLog = session?.powerLog {
            captured.powerLog = powerLog.path(percentEncoded: false)
            bookmark = captured
        }
        momentTimelineCount = count
        momentLock.withLock { moment = bookmark }
    }

    /// The setup the engines run with: what a bookmark's replay needs to reach the same state.
    var engineSetup: EngineSetup { lock.withLock { setup } }

    /// Stores a bookmark in its game's record and saves it, off the main thread: finds the log
    /// stretch's byte offsets first (lines already read never move, since the log only grows).
    /// `completion` gets false when neither the engine nor the record store knows its game.
    func save(_ bookmark: FeedbackBookmark, completion: @escaping @Sendable (Bool) -> Void) {
        controlQueue.async { [self] in
            var bookmark = bookmark
            if let path = bookmark.powerLog {
                bookmark.cut = bookmark.cut.locating(in: URL(filePath: path))
            }
            let added = lock.withLock {
                guard engine.addBookmark(bookmark) else { return false }
                saveRecords()
                return true
            }
            // The session changed while the note was typed: the game is on disk, if anywhere.
            completion(added || (try? records?.add(bookmark)) == true)
        }
    }

    /// Call with `lock` held.
    private func saveRecords() {
        for record in engine.takeUnsavedRecords() {
            try? records?.save(record)
            if record.outcome.isFinal, let seed = record.gameSeed, endedGames.insert(seed).inserted {
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
        if preview != lastOddsPreview {
            lastOddsPreview = preview
            onOddsPreview(preview)
        }
        // The advisor's state: the same combat, plus the gold, shop, hand and buttons.
        let advisor = preview == nil ? nil : engine.advisorRequest
        if advisor != lastAdvisorRequest {
            lastAdvisorRequest = advisor
            onAdvisorRequest(advisor)
        }
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
