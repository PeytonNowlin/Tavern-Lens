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
    /// The size of the followed session's Power.log, checked every few seconds.
    private(set) var powerLogBytes: Int64?

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
        }) { [weak self] update in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.update = update
            }
        }
        self.pipeline = pipeline
        pipeline.start(logsDirectory: Self.locations(for: client).logsDirectory, launchDate: client.launchDate)
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
