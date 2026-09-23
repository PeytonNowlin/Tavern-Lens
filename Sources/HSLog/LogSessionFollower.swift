import Darwin
import Foundation

/// Follows the live Hearthstone log session: finds the newest session folder, tails
/// the chosen log files in it, and switches when a newer folder appears (the client
/// restarted).
///
/// Each file is read from its start, so a session joined late is caught up in
/// order; lines are delivered in batches of up to about a megabyte. A vnode source
/// on the `Logs` directory and one per file give low latency; a backup poll
/// (default 250 ms) covers missed events and folders that don't exist yet.
///
/// Events are delivered in order on one private serial queue. After `stop()` returns
/// no further events are delivered.
public final class LogSessionFollower: @unchecked Sendable {
    public enum Event: Sendable {
        /// Now following this session. Lines that follow belong to it.
        case sessionStarted(LogSession)
        /// Complete lines from one file (`LogFileName`), in file order.
        case lines(file: String, [String])
    }

    public let logsDirectory: URL
    public let fileNames: [String]
    public let launchDate: Date?

    private let pollInterval: DispatchTimeInterval
    private let timeZone: TimeZone
    private let handler: @Sendable (Event) -> Void
    private let queue = DispatchQueue(label: "TavernLens.LogSessionFollower", qos: .userInitiated)

    // Confined to `queue`.
    private var running = false
    private var timer: DispatchSourceTimer?
    private var directorySource: DispatchSourceFileSystemObject?
    private var session: LogSession?
    private var tailers: [LogFileTailer] = []

    /// - Parameters:
    ///   - launchDate: When the client launched, if known. A newest folder older than
    ///     this is a previous launch's, so it's ignored until the new one appears.
    public init(
        logsDirectory: URL,
        fileNames: [String] = [LogFileName.power, LogFileName.loadingScreen],
        launchDate: Date? = nil,
        pollInterval: DispatchTimeInterval = .milliseconds(250),
        timeZone: TimeZone = .current,
        handler: @escaping @Sendable (Event) -> Void
    ) {
        self.logsDirectory = logsDirectory
        self.fileNames = fileNames
        self.launchDate = launchDate
        self.pollInterval = pollInterval
        self.timeZone = timeZone
        self.handler = handler
    }

    public func start() {
        queue.async { [self] in
            guard !running, timer == nil else { return }
            running = true
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: pollInterval, leeway: .milliseconds(50))
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.activate()
        }
    }

    /// Stops following. Blocks until any in-flight delivery has finished.
    public func stop() {
        queue.sync { [self] in
            running = false
            timer?.cancel()
            timer = nil
            directorySource?.cancel()
            directorySource = nil
            tailers.forEach { $0.stop() }
            tailers = []
            session = nil
        }
    }

    // MARK: - On the queue

    private func tick() {
        guard running else { return }
        if directorySource == nil { watchDirectory() }
        let live = LogSessionDiscovery.liveSession(in: logsDirectory, launchedAt: launchDate, timeZone: timeZone)
        if let live, live != session {
            follow(live)
        }
        pollFiles()
    }

    private func follow(_ newSession: LogSession) {
        tailers.forEach { $0.stop() }
        session = newSession
        handler(.sessionStarted(newSession))
        tailers = fileNames.map { name in
            LogFileTailer(url: newSession.file(named: name), queue: queue) { [weak self] lines in
                guard let self, self.running else { return }
                self.handler(.lines(file: name, lines))
            }
        }
    }

    private func pollFiles() {
        for tailer in tailers where running {
            tailer.poll()
        }
    }

    private func watchDirectory() {
        let descriptor = open(logsDirectory.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            if !source.data.isDisjoint(with: [.delete, .rename]) {
                // The Logs folder itself went away; re-open it on a later tick.
                self.directorySource?.cancel()
                self.directorySource = nil
            }
            self.tick()
        }
        source.setCancelHandler { close(descriptor) }
        directorySource = source
        source.activate()
    }
}
