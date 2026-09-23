import Foundation
import HSLog
import Testing

@Suite("Session discovery")
struct SessionDiscoveryTests {
    let utc = TimeZone(identifier: "UTC")!

    @Test("The newest session folder is chosen by its name's timestamp")
    func newest() throws {
        let install = try TemporaryInstall()
        try install.makeSession("Hearthstone_2026_09_22_20_31_46")
        try install.makeSession("Hearthstone_2026_09_22_21_08_40")
        try install.makeSession("Hearthstone_2026_09_22_20_33_28")
        // Not sessions: wrong names, and a file with a session-like name.
        try install.makeSession("Hearthstone_2026_09_22_99_99_99")
        try install.makeSession("Hearthstone_latest")
        try install.makeSession("Other_2027_01_01_00_00_00")
        try install.write("", to: install.locations.logsDirectory.appending(path: "Hearthstone_2027_01_01_00_00_00"))

        let sessions = LogSessionDiscovery.sessions(in: install.locations.logsDirectory, timeZone: utc)
        #expect(sessions.map(\.name) == [
            "Hearthstone_2026_09_22_20_31_46", "Hearthstone_2026_09_22_20_33_28", "Hearthstone_2026_09_22_21_08_40",
        ])
        let newest = try #require(LogSessionDiscovery.newestSession(in: install.locations.logsDirectory, timeZone: utc))
        #expect(newest.name == "Hearthstone_2026_09_22_21_08_40")
        #expect(newest.started == Date(timeIntervalSince1970: 1_790_111_320))
        #expect(newest.powerLog.lastPathComponent == "Power.log")
    }

    @Test("A day boundary still sorts chronologically")
    func acrossMidnight() throws {
        let install = try TemporaryInstall()
        try install.makeSession("Hearthstone_2026_09_22_23_59_59")
        try install.makeSession("Hearthstone_2026_09_23_00_00_01")
        let newest = LogSessionDiscovery.newestSession(in: install.locations.logsDirectory, timeZone: utc)
        #expect(newest?.name == "Hearthstone_2026_09_23_00_00_01")
    }

    @Test("No Logs folder, or an empty one, has no session")
    func none() throws {
        let install = try TemporaryInstall()
        #expect(LogSessionDiscovery.newestSession(in: install.locations.logsDirectory) == nil)
        try FileManager.default.createDirectory(at: install.locations.logsDirectory, withIntermediateDirectories: true)
        #expect(LogSessionDiscovery.newestSession(in: install.locations.logsDirectory) == nil)
    }

    @Test("A folder from before the running client's launch isn't its session")
    func liveSessionRespectsLaunch() throws {
        let install = try TemporaryInstall()
        try install.makeSession("Hearthstone_2026_09_22_20_33_28")
        let logs = install.locations.logsDirectory
        let previousLaunch = try #require(LogSessionDiscovery.newestSession(in: logs, timeZone: utc)).started

        // Launched an hour later: the old folder is ignored until the new one appears.
        let launch = previousLaunch.addingTimeInterval(3600)
        #expect(LogSessionDiscovery.liveSession(in: logs, launchedAt: launch, timeZone: utc) == nil)
        try install.makeSession("Hearthstone_2026_09_22_21_33_29")
        #expect(LogSessionDiscovery.liveSession(in: logs, launchedAt: launch, timeZone: utc)?.name == "Hearthstone_2026_09_22_21_33_29")

        // Joined long after launch, or the folder name a few seconds before the launch date: still live.
        #expect(LogSessionDiscovery.liveSession(in: logs, launchedAt: launch.addingTimeInterval(5), timeZone: utc) != nil)
        #expect(LogSessionDiscovery.liveSession(in: logs, launchedAt: nil, timeZone: utc)?.name == "Hearthstone_2026_09_22_21_33_29")
    }
}
