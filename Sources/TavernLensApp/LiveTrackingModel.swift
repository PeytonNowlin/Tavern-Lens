import AppKit
import Foundation
import HSLog
import Observation
import TavernEngine

/// Live tracking for the menu bar: watches for Hearthstone and HSTracker, keeps the
/// log config correct, and follows the live log session while Hearthstone runs.
@MainActor
@Observable
final class LiveTrackingModel {
    /// HSTracker's bundle ID. It can delete or rewrite the logs Tavern Lens reads.
    static let hstrackerBundleIdentifier = "net.hearthsim.hstracker"

    struct RunningClient: Equatable {
        var processIdentifier: pid_t
        var launchDate: Date?
        var bundleURL: URL?
    }

    private(set) var hearthstone: RunningClient?
    private(set) var hstrackerRunning = false
    private(set) var restartRequired = false
    private(set) var configFailures: [String] = []
    private(set) var update = LiveUpdate(session: nil, state: .noGame, scene: nil) {
        didSet { if oldValue.session != update.session { refreshPowerLogSize() } }
    }
    /// The odds of the latest combat, simulated as it starts.
    let combatOdds = CombatOddsModel()
    /// The size of the followed session's Power.log, checked every few seconds.
    private(set) var powerLogBytes: Int64?

    /// The minion pool the live pipeline infers tribes with.
    @ObservationIgnored var pool: MinionPool? {
        didSet {
            Self.engineSetup.pool = pool
            pipeline?.usePool(pool)
        }
    }

    @ObservationIgnored var trinketStats: TrinketStats? {
        didSet {
            Self.engineSetup.trinketStats = trinketStats
            pipeline?.useTrinketStats(trinketStats)
        }
    }

    /// Firestone's hero stats and the card data the hero pick joins them with.
    @ObservationIgnored var heroStats: (stats: HeroStatsSet?, cards: CardDB?) = (nil, nil) {
        didSet {
            Self.engineSetup.heroStats = heroStats.stats
            Self.engineSetup.heroCards = heroStats.cards
            pipeline?.useHeroStats(heroStats.stats, cards: heroStats.cards)
        }
    }

    /// The build catalog the live pipeline detects builds with.
    @ObservationIgnored var builds: BuildCatalog? {
        didSet {
            Self.engineSetup.builds = builds
            pipeline?.useBuilds(builds)
        }
    }

    /// The setup every live engine gets (pool, builds, hero stats): what the debug window's
    /// bookmark replays and exports use, so they reach the state the overlay showed.
    static private(set) var engineSetup = EngineSetup()

    /// Called on the main actor when a game ends (log housekeeping runs then).
    @ObservationIgnored var onGameEnded: (@MainActor () -> Void)?

    @ObservationIgnored private var setup = LogSetup(locations: .standard)
    @ObservationIgnored private var pipeline: LivePipeline?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var sizeTimer: Timer?
    static let powerLogSizeInterval: TimeInterval = 15

    /// The logs folder of the running client, or of the standard install.
    var logsDirectory: URL { Self.locations(for: hearthstone).logsDirectory }

    var status: LiveStatus {
        LiveStatus(
            hearthstoneRunning: hearthstone != nil,
            restartRequired: restartRequired,
            followingSession: update.session != nil,
            view: update.state,
            scene: update.scene
        )
    }

    /// Starts watching. Call once, at launch.
    func start() {
        combatOdds.warmUp()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshProcesses() }
            })
        }
        // Repair the config even when Hearthstone isn't running, so its next launch logs.
        if Self.findHearthstone() == nil {
            checkConfig(hearthstoneRunning: false, locations: .standard)
        }
        refreshProcesses()
        sizeTimer = Timer.scheduledTimer(withTimeInterval: Self.powerLogSizeInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPowerLogSize() }
        }
    }

    private func refreshPowerLogSize() {
        let size = update.session.flatMap { PowerLogSizeHint.size(of: $0.powerLog) }
        if size != powerLogBytes { powerLogBytes = size }
    }

    private func refreshProcesses() {
        let apps = NSWorkspace.shared.runningApplications
        hstrackerRunning = apps.contains {
            $0.bundleIdentifier == Self.hstrackerBundleIdentifier || $0.localizedName == "HSTracker"
        }
        let found = Self.findHearthstone()
        guard found != hearthstone else { return }
        if hearthstone != nil {
            // That client quit; the next launch reads whatever config is on disk.
            setup.hearthstoneTerminated()
        }
        hearthstone = found
        stopFollowing()
        if let found {
            // A patch may have landed: card data (and the pool and hero stats built on it)
            // follows the build that's running.
            CardDataModel.shared.reloadIfBuildChanged(appURL: found.bundleURL)
            // A launch has read, or is about to read, the config, so a fix made now
            // only takes effect after a restart.
            checkConfig(hearthstoneRunning: true, locations: Self.locations(for: found))
            startFollowing(found)
        } else {
            restartRequired = setup.restartRequired
        }
    }

    private func checkConfig(hearthstoneRunning: Bool, locations: HearthstoneLocations) {
        if setup.locations != locations {
            setup = LogSetup(locations: locations)
        }
        let report = setup.check(hearthstoneRunning: hearthstoneRunning)
        let wasRequired = restartRequired
        restartRequired = setup.restartRequired
        configFailures = report.failures
        if restartRequired, !wasRequired {
            Task { @MainActor in Self.showRestartNotice() }
        }
    }

    /// A one-time notice; the menu bar keeps saying "Restart Hearthstone required" until it quits.
    private static func showRestartNotice() {
        let alert = NSAlert()
        alert.messageText = "Restart Hearthstone"
        alert.informativeText = "Tavern Lens fixed Hearthstone's log settings. Hearthstone reads them only when it starts, "
            + "so quit and reopen it before your next game."
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }

    private func startFollowing(_ client: RunningClient) {
        generation += 1
        let token = generation
        let pipeline = LivePipeline(records: .standard, onGameEnded: { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.onGameEnded?()
            }
        }, onCombatRequest: { [weak self] request in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.combatOdds.start(request)
            }
        }, onOddsPreview: { [weak self] preview in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.combatOdds.preview(preview)
            }
        }, onAdvisorRequest: { [weak self] request in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.combatOdds.advise(request)
            }
        }) { [weak self] update in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.update = update
            }
        }
        self.pipeline = pipeline
        pipeline.usePool(pool)
        pipeline.useHeroStats(heroStats.stats, cards: heroStats.cards)
        pipeline.useBuilds(builds)
        pipeline.useTrinketStats(trinketStats)
        pipeline.start(logsDirectory: Self.locations(for: client).logsDirectory, launchDate: client.launchDate)
    }

    /// The lobby's tribes read from the hero-pick banner, for the game in progress.
    func ingestScreenTribes(_ reading: ScreenTribeReading) {
        pipeline?.ingestScreenTribes(reading)
    }

    /// The moment on screen as a bookmark with no note yet; nil with no game shown. Instant: no
    /// log or disk access here.
    func captureBookmark() -> FeedbackBookmark? {
        pipeline?.captureBookmark()
    }

    /// Stores a bookmark in its game's record, off the main thread; `completion` (on the main
    /// actor) gets false when its game is unknown.
    func save(_ bookmark: FeedbackBookmark, completion: @escaping @MainActor (Bool) -> Void) {
        let done: @Sendable (Bool) -> Void = { saved in Task { @MainActor in completion(saved) } }
        if let pipeline {
            pipeline.save(bookmark, completion: done)
        } else {
            Task.detached(priority: .userInitiated) {
                var bookmark = bookmark
                if let path = bookmark.powerLog { bookmark.cut = bookmark.cut.locating(in: URL(filePath: path)) }
                done((try? GameRecordStore.standard.add(bookmark)) == true)
            }
        }
    }

    private func stopFollowing() {
        generation += 1
        pipeline?.stop()
        pipeline = nil
        update = LiveUpdate(session: nil, state: .noGame, scene: nil)
    }

    private static func findHearthstone() -> RunningClient? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == HearthstoneLocations.bundleIdentifier && !$0.isTerminated }
            .map { RunningClient(processIdentifier: $0.processIdentifier, launchDate: $0.launchDate, bundleURL: $0.bundleURL) }
    }

    private static func locations(for client: RunningClient?) -> HearthstoneLocations {
        .forRunningApp(bundleURL: client?.bundleURL)
    }
}
