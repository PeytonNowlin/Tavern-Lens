import Foundation
import HSLog
import os

/// Every disk-use limit the player can change in settings. Defaults follow the spec.
public struct RetentionSettings: Codable, Hashable, Sendable {
    /// Hearthstone log session folders to keep (default 10).
    public var maxSessions = 10
    /// Size cap for the log session folders together (default 2 GB).
    public var maxLogBytes: Int64 = 2 * ByteSize.gigabyte
    /// Whether to save each game's compressed log slice as a replay.
    public var keepReplays = true
    /// Replays to keep, newest first (default 40 games).
    public var maxReplays = ReplayStore.defaultLimit
    /// Show the menu-bar hint once the current Power.log is this big (default 800 MB).
    public var powerLogHintBytes = PowerLogSizeHint.defaultThreshold
    /// Size cap for the card art cache (default 1 GB).
    public var maxArtCacheBytes = ArtCache.defaultLimit

    public init() {}

    public var logPolicy: LogRetentionPolicy {
        LogRetentionPolicy(maxSessions: maxSessions, maxTotalBytes: maxLogBytes)
    }

    /// Settings saved by an older version may lack newer keys; those get defaults.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = RetentionSettings()
        maxSessions = try container.decodeIfPresent(Int.self, forKey: .maxSessions) ?? defaults.maxSessions
        maxLogBytes = try container.decodeIfPresent(Int64.self, forKey: .maxLogBytes) ?? defaults.maxLogBytes
        keepReplays = try container.decodeIfPresent(Bool.self, forKey: .keepReplays) ?? defaults.keepReplays
        maxReplays = try container.decodeIfPresent(Int.self, forKey: .maxReplays) ?? defaults.maxReplays
        powerLogHintBytes = try container.decodeIfPresent(Int64.self, forKey: .powerLogHintBytes) ?? defaults.powerLogHintBytes
        maxArtCacheBytes = try container.decodeIfPresent(Int64.self, forKey: .maxArtCacheBytes) ?? defaults.maxArtCacheBytes
    }
}

/// What one housekeeping pass did.
public struct HousekeepingReport: Hashable, Sendable {
    public var logs = LogPruneReport()
    /// Session folders whose games were read into records before they were deleted.
    public var importedSessions: [String] = []
    /// Game records written by those imports.
    public var importedRecords = 0
    public var replaysSaved: [ReplayFile] = []
    public var replaysDeleted: [ReplayFile] = []
    public var art = ArtCache.PruneResult()

    public init() {}
}

/// Keeps disk use bounded (spec: "Storage and log retention"). One `run` is a pass:
///
/// 1. Replays: each finished game in the newest session gets its compressed slice
///    saved, if replays are on.
/// 2. Hearthstone's old log sessions are pruned, oldest first, until both limits
///    hold (`LogRetention`). The newest session and any session a process has open
///    are never touched. Before a session goes, its games are read into game records
///    (an earlier game of that client launch the app never saw has none yet) and
///    their slices saved as replays; if a game can't be recorded, the session stays.
/// 3. Replays over their cap are deleted, oldest first.
/// 4. The art cache is trimmed to its cap, least recently used first.
///
/// It reads the settings it's given each pass, so a change applies to the next pass.
/// Run it at launch and after each game ends, never twice at once.
public struct LogHousekeeper: Sendable {
    static let logger = Logger(subsystem: "com.nowlinautomation.TavernLens", category: "retention")

    public var logsDirectory: URL
    public var records: GameRecordStore
    public var replays: ReplayStore
    public var artCache: ArtCache?
    public var timeZone: TimeZone

    public init(
        logsDirectory: URL, records: GameRecordStore, replays: ReplayStore, artCache: ArtCache? = nil,
        timeZone: TimeZone = .current
    ) {
        self.logsDirectory = logsDirectory
        self.records = records
        self.replays = replays
        self.artCache = artCache
        self.timeZone = timeZone
    }

    /// One pass. `activeSessions` names session folders to leave alone besides the
    /// newest (the one the app is following, say).
    @discardableResult
    public func run(settings: RetentionSettings, activeSessions: Set<String> = []) -> HousekeepingReport {
        var report = HousekeepingReport()
        if settings.keepReplays,
           let newest = LogSessionDiscovery.newestSession(in: logsDirectory, timeZone: timeZone) {
            report.replaysSaved += saveReplays(of: newest, finishedOnly: true)
        }
        report.logs = LogRetention.prune(
            logsDirectory: logsDirectory, policy: settings.logPolicy, activeSessions: activeSessions, timeZone: timeZone
        ) { session in
            guard let imported = importGames(of: session) else { return false }
            report.importedSessions.append(session.name)
            report.importedRecords += imported
            if settings.keepReplays {
                report.replaysSaved += saveReplays(of: session, finishedOnly: false)
            }
            return true
        }
        report.replaysDeleted = replays.prune(keeping: settings.maxReplays, timeZone: timeZone)
        if let artCache {
            report.art = artCache.prune(maxBytes: settings.maxArtCacheBytes)
        }
        for replay in report.replaysDeleted {
            Self.logger.notice("Deleted replay \(replay.url.lastPathComponent, privacy: .public)")
        }
        if report.art.filesDeleted > 0 {
            Self.logger.notice("Trimmed the art cache by \(ByteSize.format(report.art.bytesFreed), privacy: .public)")
        }
        return report
    }

    /// Makes sure every solo Battlegrounds game in a session's Power.log has a game
    /// record: the log is replayed and records that are missing, or older than what the
    /// log holds, are saved. Returns how many were saved, or nil if a game still has no
    /// record (the log can't be read, or saving failed).
    public func importGames(of session: LogSession) -> Int? {
        let powerLog = session.powerLog
        guard FileManager.default.fileExists(atPath: powerLog.path(percentEncoded: false)) else { return 0 }
        let slices = PowerLogGames.slices(in: powerLog)
        let alreadyRecorded = slices.allSatisfy { slice in
            guard let seed = slice.gameSeed, let stored = records.load(seed: seed) else { return false }
            return stored.sessions.contains(session.name)
        }
        if alreadyRecorded { return 0 }

        var engine = TavernEngine(session: session, timeZone: timeZone)
        // A game this launch resumed from an earlier one (the client restarted mid-game).
        if let seed = slices.first?.gameSeed, let stored = records.load(seed: seed),
           stored.outcome.isResumable, !stored.sessions.contains(session.name) {
            engine.resume(stored)
        }
        do {
            try LogFileReader.forEachLine(in: powerLog) { engine.ingest($0) }
        } catch {
            Self.logger.error("Couldn't read \(session.name, privacy: .public)/Power.log: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        engine.finish()

        var saved = 0
        for record in engine.records {
            let stored = record.gameSeed.flatMap { records.load(seed: $0) }
            if let stored, (stored.updatedAt ?? .distantPast) >= (record.updatedAt ?? .distantPast) { continue }
            do {
                try records.save(record)
                saved += 1
            } catch {
                Self.logger.error("Couldn't save the record of a game in \(session.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        let allRecorded = engine.records.allSatisfy {
            FileManager.default.fileExists(atPath: records.url(for: $0).path(percentEncoded: false))
        }
        if saved > 0 {
            Self.logger.notice("Recorded \(saved) game(s) from \(session.name, privacy: .public)")
        }
        return allRecorded ? saved : nil
    }

    /// Saves the slices of a session's recorded games that have no replay yet. With
    /// `finishedOnly`, only games whose record says they're over (the session may
    /// still be growing).
    public func saveReplays(of session: LogSession, finishedOnly: Bool) -> [ReplayFile] {
        let powerLog = session.powerLog
        guard let data = try? Data(contentsOf: powerLog, options: .alwaysMapped) else { return [] }
        var saved: [ReplayFile] = []
        for slice in PowerLogGames.slices(in: data) {
            guard let seed = slice.gameSeed, let record = records.load(seed: seed),
                  !finishedOnly || record.outcome.isFinal,
                  !replays.contains(sessionName: session.name, line: slice.line, gameSeed: seed)
            else { continue }
            do {
                saved.append(try replays.save(slice, of: data, sessionName: session.name))
            } catch {
                Self.logger.error("Couldn't save a replay from \(session.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return saved
    }
}
