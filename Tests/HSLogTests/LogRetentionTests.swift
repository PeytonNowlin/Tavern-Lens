import Foundation
import HSLog
import Testing

/// Seam 3: pruning Hearthstone's log session folders in a temporary install tree.
@Suite("Log retention")
struct LogRetentionTests {
    /// Session folders a day apart, oldest first.
    static func names(_ count: Int) -> [String] {
        (0..<count).map { String(format: "Hearthstone_2026_09_%02d_20_00_00", $0 + 1) }
    }

    /// Makes sessions with a Power.log of `bytes` each (plus a small other log).
    static func install(sessions names: [String], bytes: Int = 1000) throws -> TemporaryInstall {
        let install = try TemporaryInstall()
        for name in names {
            let folder = try install.makeSession(name)
            try Data(repeating: 0x41, count: bytes - 10).write(to: folder.appending(path: "Power.log"))
            try Data(repeating: 0x42, count: 10).write(to: folder.appending(path: "LoadingScreen.log"))
        }
        return install
    }

    static func remaining(_ install: TemporaryInstall) -> [String] {
        LogSessionDiscovery.sessions(in: install.locations.logsDirectory).map(\.name)
    }

    @Test("Over the session limit, the oldest folders go first")
    func keepsNewestSessions() throws {
        let names = Self.names(13)
        let install = try Self.install(sessions: names)
        var prepared: [String] = []
        let report = LogRetention.prune(
            logsDirectory: install.locations.logsDirectory, policy: LogRetentionPolicy()
        ) { prepared.append($0.name); return true }

        #expect(report.deleted == Array(names.prefix(3)))
        #expect(prepared == Array(names.prefix(3)))
        #expect(Self.remaining(install) == Array(names.suffix(10)))
        #expect(report.sessionsRemaining == 10)
        #expect(report.bytesFreed == 3000)
        #expect(report.bytesRemaining == 10_000)
    }

    @Test("Under both limits, nothing is touched or even prepared")
    func underLimits() throws {
        let names = Self.names(4)
        let install = try Self.install(sessions: names)
        let report = LogRetention.prune(
            logsDirectory: install.locations.logsDirectory, policy: LogRetentionPolicy(maxSessions: 4, maxTotalBytes: 4000)
        ) { _ in Issue.record("nothing should be prepared"); return true }
        #expect(report.deleted.isEmpty)
        #expect(Self.remaining(install) == names)
    }

    @Test("Over the size cap, the oldest folders go until it's respected")
    func sizeCap() throws {
        let names = Self.names(6)
        let install = try Self.install(sessions: names)
        let report = LogRetention.prune(
            logsDirectory: install.locations.logsDirectory, policy: LogRetentionPolicy(maxSessions: 10, maxTotalBytes: 3500)
        ) { _ in true }
        #expect(report.deleted == Array(names.prefix(3)))
        #expect(report.bytesRemaining == 3000)
        #expect(Self.remaining(install) == Array(names.suffix(3)))
    }

    @Test("The newest folder is never deleted, even alone over the cap")
    func newestIsKept() throws {
        let names = Self.names(3)
        let install = try Self.install(sessions: names, bytes: 5000)
        let report = LogRetention.prune(
            logsDirectory: install.locations.logsDirectory, policy: LogRetentionPolicy(maxSessions: 0, maxTotalBytes: 0)
        ) { _ in true }
        #expect(report.deleted == Array(names.prefix(2)))
        #expect(report.kept == [names[2]: .newest])
        #expect(Self.remaining(install) == [names[2]])
    }

    @Test("A folder named active is kept; a younger one goes instead")
    func activeIsKept() throws {
        let names = Self.names(5)
        let install = try Self.install(sessions: names)
        let report = LogRetention.prune(
            logsDirectory: install.locations.logsDirectory, policy: LogRetentionPolicy(maxSessions: 3, maxTotalBytes: .max),
            activeSessions: [names[0]]
        ) { _ in true }
        #expect(report.kept == [names[0]: .active])
        #expect(report.deleted == [names[1], names[2]])
        #expect(Self.remaining(install) == [names[0], names[3], names[4]])
    }

    @Test("A folder with a file some process has open is kept (proc_listpidspath)")
    func openFileIsKept() throws {
        let names = Self.names(4)
        let install = try Self.install(sessions: names)
        let open = install.locations.logsDirectory.appending(path: names[0]).appending(path: "Power.log")
        let handle = try FileHandle(forReadingFrom: open)
        defer { try? handle.close() }
        let session = try #require(LogSessionDiscovery.sessions(in: install.locations.logsDirectory).first)
        #expect(ActiveLogSessions.isOpen(session))

        let report = LogRetention.prune(
            logsDirectory: install.locations.logsDirectory, policy: LogRetentionPolicy(maxSessions: 1, maxTotalBytes: .max)
        ) { _ in true }
        #expect(report.kept[names[0]] == .active)
        #expect(report.deleted == [names[1], names[2]])
        #expect(Self.remaining(install) == [names[0], names[3]])

        try handle.close()
        #expect(!ActiveLogSessions.isOpen(session))
        let next = LogRetention.prune(
            logsDirectory: install.locations.logsDirectory, policy: LogRetentionPolicy(maxSessions: 1, maxTotalBytes: .max)
        ) { _ in true }
        #expect(next.deleted == [names[0]])
    }

    @Test("A folder whose games can't be recorded is never deleted")
    func unrecordedIsKept() throws {
        let names = Self.names(5)
        let install = try Self.install(sessions: names)
        let unrecorded: Set = [names[0], names[2]]
        let report = LogRetention.prune(
            logsDirectory: install.locations.logsDirectory, policy: LogRetentionPolicy(maxSessions: 1, maxTotalBytes: .max)
        ) { !unrecorded.contains($0.name) }
        #expect(report.deleted == [names[1], names[3]])
        #expect(report.kept == [names[0]: .unrecorded, names[2]: .unrecorded, names[4]: .newest])
        #expect(Self.remaining(install) == [names[0], names[2], names[4]])
    }

    @Test("Only session folders are touched; other files in Logs stay")
    func otherEntriesStay() throws {
        let names = Self.names(3)
        let install = try Self.install(sessions: names)
        let logs = install.locations.logsDirectory
        let stray = logs.appending(path: "notes.txt")
        try install.write("keep me", to: stray)
        let otherFolder = logs.appending(path: "Hearthstone_backup", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: otherFolder, withIntermediateDirectories: true)

        let report = LogRetention.prune(logsDirectory: logs, policy: LogRetentionPolicy(maxSessions: 0, maxTotalBytes: 0)) { _ in true }
        #expect(report.deleted == Array(names.prefix(2)))
        #expect(install.exists(stray))
        #expect(install.exists(otherFolder))
    }

    @Test("A policy change applies to the next pass")
    func policyChange() throws {
        let names = Self.names(8)
        let install = try Self.install(sessions: names)
        let logs = install.locations.logsDirectory
        var policy = LogRetentionPolicy(maxSessions: 6, maxTotalBytes: .max)
        #expect(LogRetention.prune(logsDirectory: logs, policy: policy) { _ in true }.deleted == Array(names.prefix(2)))
        policy.maxSessions = 4
        #expect(LogRetention.prune(logsDirectory: logs, policy: policy) { _ in true }.deleted == Array(names[2..<4]))
        policy.maxTotalBytes = 2500
        #expect(LogRetention.prune(logsDirectory: logs, policy: policy) { _ in true }.deleted == Array(names[4..<6]))
        #expect(Self.remaining(install) == Array(names.suffix(2)))
    }

    @Test("No Logs folder: nothing to do")
    func noLogs() throws {
        let install = try TemporaryInstall()
        let report = LogRetention.prune(logsDirectory: install.locations.logsDirectory, policy: LogRetentionPolicy()) { _ in true }
        #expect(report == LogPruneReport())
    }
}

@Suite("Power.log size hint")
struct PowerLogSizeHintTests {
    @Test("Shown from the threshold on, with the size")
    func hint() throws {
        #expect(PowerLogSizeHint.message(bytes: 799_999_999) == nil)
        #expect(PowerLogSizeHint.message(bytes: 800_000_000) == "Power.log is 800 MB; restart Hearthstone to rotate")
        #expect(PowerLogSizeHint.message(bytes: 812_400_000)?.hasPrefix("Power.log is 812") == true)
        #expect(PowerLogSizeHint.message(bytes: 5_000, threshold: 4_000) != nil)
        #expect(PowerLogSizeHint.message(bytes: 5_000, threshold: 0) == nil)
    }

    @Test("Reads the current size of a growing file")
    func size() throws {
        let install = try TemporaryInstall()
        let log = try install.makeSession("Hearthstone_2026_09_22_20_00_00").appending(path: "Power.log")
        #expect(PowerLogSizeHint.size(of: log) == nil)
        try install.append("12345\n", to: log)
        #expect(PowerLogSizeHint.size(of: log) == 6)
        try install.append("67890\n", to: log)
        #expect(PowerLogSizeHint.size(of: log) == 12)
    }
}
