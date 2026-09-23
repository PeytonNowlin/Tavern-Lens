import Darwin
import Foundation
import os

/// How many Hearthstone log sessions to keep, and how much disk they may use.
public struct LogRetentionPolicy: Codable, Hashable, Sendable {
    /// Keep at most this many session folders (default 10).
    public var maxSessions: Int
    /// Keep the session folders together under this many bytes (default 2 GB).
    public var maxTotalBytes: Int64

    public init(maxSessions: Int = 10, maxTotalBytes: Int64 = 2 * ByteSize.gigabyte) {
        self.maxSessions = maxSessions
        self.maxTotalBytes = maxTotalBytes
    }
}

/// Decimal byte units, as Finder shows sizes.
public enum ByteSize {
    public static let megabyte: Int64 = 1_000_000
    public static let gigabyte: Int64 = 1_000_000_000

    /// "812 MB", "2.1 GB".
    public static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// What one pruning pass did.
public struct LogPruneReport: Hashable, Sendable {
    public enum KeepReason: String, Hashable, Sendable {
        /// The newest folder: the one Hearthstone writes, or will write next.
        case newest
        /// A process (Hearthstone) has one of its files open, or the caller named it active.
        case active
        /// Its games couldn't be recorded first, so its logs are the only copy.
        case unrecorded
        /// Deleting it failed.
        case deleteFailed
    }

    /// Deleted folder names, oldest first.
    public var deleted: [String] = []
    /// Folders the limits wanted gone but that were kept, with why.
    public var kept: [String: KeepReason] = [:]
    public var bytesFreed: Int64 = 0
    /// Sessions and bytes left in `Logs/` after the pass.
    public var sessionsRemaining = 0
    public var bytesRemaining: Int64 = 0

    public init() {}
}

/// Prunes Hearthstone's old log session folders (`Logs/Hearthstone_*`), oldest first,
/// until both limits of the policy hold. Hearthstone makes a folder per launch and
/// doesn't seem to prune them, and with the size cap lifted one game writes 35 MB or
/// more.
///
/// Never deleted: the newest folder, any folder whose files a process has open or
/// that the caller says is active, and any folder that `prepare` couldn't record
/// (`prepare` imports the folder's games before it goes; it returns false when they
/// aren't all recorded). Those still count towards the limits, so a younger folder
/// may go instead. Nothing else in `Logs/` is touched.
public enum LogRetention {
    static let logger = Logger(subsystem: "com.nowlinautomation.TavernLens", category: "retention")

    @discardableResult
    public static func prune(
        logsDirectory: URL,
        policy: LogRetentionPolicy,
        activeSessions: Set<String> = [],
        timeZone: TimeZone = .current,
        prepare: (LogSession) -> Bool
    ) -> LogPruneReport {
        let sessions = LogSessionDiscovery.sessions(in: logsDirectory, timeZone: timeZone)
        var sizes = Dictionary(uniqueKeysWithValues: sessions.map { ($0.name, directorySize($0.directory)) })
        var count = sessions.count
        var total = sizes.values.reduce(0, +)
        var report = LogPruneReport()
        func overLimit() -> Bool { count > max(0, policy.maxSessions) || total > max(0, policy.maxTotalBytes) }

        for session in sessions where overLimit() {
            if session == sessions.last {
                report.kept[session.name] = .newest
                continue
            }
            if activeSessions.contains(session.name) || ActiveLogSessions.isOpen(session) {
                report.kept[session.name] = .active
                continue
            }
            guard prepare(session) else {
                report.kept[session.name] = .unrecorded
                logger.notice("Kept log session \(session.name, privacy: .public): its games aren't recorded")
                continue
            }
            do {
                try FileManager.default.removeItem(at: session.directory)
            } catch {
                report.kept[session.name] = .deleteFailed
                logger.error("Couldn't delete log session \(session.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                continue
            }
            let size = sizes.removeValue(forKey: session.name) ?? 0
            count -= 1
            total -= size
            report.deleted.append(session.name)
            report.bytesFreed += size
            logger.notice("Deleted log session \(session.name, privacy: .public) (\(ByteSize.format(size), privacy: .public))")
        }
        report.sessionsRemaining = count
        report.bytesRemaining = total
        return report
    }

    /// The bytes a folder's files take up, recursively.
    public static func directorySize(_ directory: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(keys)) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}

/// Which log sessions a process is writing, found the way HSTracker does: by asking
/// the kernel which processes have a file open at a path (`proc_listpidspath`).
public enum ActiveLogSessions {
    /// Whether any process has one of the session folder's files open.
    public static func isOpen(_ session: LogSession) -> Bool {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: session.directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return files.contains(where: isOpen(file:))
    }

    /// Whether any process has the file at `url` open.
    public static func isOpen(file url: URL) -> Bool {
        var pids = [pid_t](repeating: 0, count: 64)
        let bytes = url.path(percentEncoded: false).withCString { path in
            pids.withUnsafeMutableBytes { buffer in
                proc_listpidspath(UInt32(PROC_ALL_PIDS), 0, path, 0, buffer.baseAddress, Int32(buffer.count))
            }
        }
        return bytes > 0 && pids.contains { $0 > 0 }
    }
}
