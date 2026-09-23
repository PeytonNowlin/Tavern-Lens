import Foundation

/// One Hearthstone client launch: a `Logs/Hearthstone_YYYY_MM_DD_HH_MM_SS` folder.
///
/// Every log of a launch (all games, all modes) is appended to that folder's files.
/// The folder name's timestamp is local time and equals the first log line's time.
public struct LogSession: Hashable, Sendable {
    public var directory: URL
    /// The folder name, e.g. `Hearthstone_2026_09_22_21_08_40`.
    public var name: String
    /// When the client launched, parsed from the folder name.
    public var started: Date

    public var powerLog: URL { file(named: LogFileName.power) }
    public var loadingScreenLog: URL { file(named: LogFileName.loadingScreen) }

    public func file(named name: String) -> URL {
        directory.appending(path: name)
    }

    /// Parses a session folder name. Returns nil for anything else in `Logs/`.
    public init?(directory: URL, timeZone: TimeZone = .current) {
        let name = directory.lastPathComponent
        let prefix = "Hearthstone_"
        guard name.hasPrefix(prefix) else { return nil }
        let fields = name.dropFirst(prefix.count).split(separator: "_", omittingEmptySubsequences: false)
        guard fields.count == 6, fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }) else { return nil }
        let numbers = fields.compactMap { Int($0) }
        var components = DateComponents()
        components.year = numbers[0]
        components.month = numbers[1]
        components.day = numbers[2]
        components.hour = numbers[3]
        components.minute = numbers[4]
        components.second = numbers[5]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard components.isValidDate(in: calendar), let started = calendar.date(from: components) else { return nil }
        self.directory = directory
        self.name = name
        self.started = started
    }
}

/// The log files Tavern Lens reads. `log.config` enables only these.
public enum LogFileName {
    public static let power = "Power.log"
    public static let loadingScreen = "LoadingScreen.log"
}

/// Finds the session folder Hearthstone is writing.
///
/// macOS has no file lock to probe (unlike HDT's Windows trick) and Tavern Lens
/// doesn't read memory (unlike HSTracker), so the live folder is the newest one by
/// its name's timestamp, provided it isn't older than the running client.
public enum LogSessionDiscovery {
    /// How much older than the client's launch a session folder may claim to be and
    /// still count as that launch's folder (clock skew, a slow launch date).
    public static let launchTolerance: TimeInterval = 120

    /// All session folders in `logsDirectory`, oldest first. Empty if it doesn't exist.
    public static func sessions(in logsDirectory: URL, timeZone: TimeZone = .current) -> [LogSession] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .compactMap { LogSession(directory: $0, timeZone: timeZone) }
            .sorted { ($0.started, $0.name) < ($1.started, $1.name) }
    }

    /// The newest session folder, if any.
    public static func newestSession(in logsDirectory: URL, timeZone: TimeZone = .current) -> LogSession? {
        sessions(in: logsDirectory, timeZone: timeZone).last
    }

    /// The session folder of a client launched at `launchDate`: the newest folder,
    /// unless it predates the launch (the new launch hasn't created its folder yet).
    /// With no launch date, the newest folder.
    public static func liveSession(
        in logsDirectory: URL,
        launchedAt launchDate: Date?,
        timeZone: TimeZone = .current
    ) -> LogSession? {
        guard let newest = newestSession(in: logsDirectory, timeZone: timeZone) else { return nil }
        if let launchDate, newest.started < launchDate.addingTimeInterval(-launchTolerance) {
            return nil
        }
        return newest
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
