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
/// 10 times a second; a catch-up of a long log therefore publishes a handful of
/// intermediate states and then the current one.
final class LivePipeline: @unchecked Sendable {
    static let minimumPublishInterval: Duration = .milliseconds(100)

    private let publish: @Sendable (LiveUpdate) -> Void
    private var follower: LogSessionFollower?

    // Guarded by `lock`: written on the follower's queue, and read by deferred flushes.
    private var engine = TavernEngine()
    private var session: LogSession?
    private var lastPublished: LiveUpdate?
    private var lastPublishTime: ContinuousClock.Instant?
    private var pendingFlush = false
    private let clock = ContinuousClock()
    private let flushQueue = DispatchQueue(label: "TavernLens.LivePipeline.flush")
    private let lock = NSLock()

    init(publish: @escaping @Sendable (LiveUpdate) -> Void) {
        self.publish = publish
    }

    func start(logsDirectory: URL, launchDate: Date?) {
        let follower = LogSessionFollower(logsDirectory: logsDirectory, launchDate: launchDate) { [weak self] event in
            self?.handle(event)
        }
        self.follower = follower
        follower.start()
    }

    func stop() {
        follower?.stop()
        follower = nil
    }

    private func handle(_ event: LogSessionFollower.Event) {
        lock.lock()
        defer { lock.unlock() }
        switch event {
        case .sessionStarted(let newSession):
            session = newSession
            engine = TavernEngine()
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
        publishIfDue()
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
