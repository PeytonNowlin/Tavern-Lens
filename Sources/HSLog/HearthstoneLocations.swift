import Foundation

/// Where Hearthstone keeps its install, its log sessions and its log config.
///
/// Everything is derived from two roots so tests can point both at a temporary
/// directory tree.
public struct HearthstoneLocations: Hashable, Sendable {
    /// The bundle ID of the game client (not the Battle.net launcher).
    public static let bundleIdentifier = "unity.Blizzard Entertainment.Hearthstone"

    /// The install directory, which holds `Hearthstone.app`, `Logs/` and `client.config`.
    public var installDirectory: URL
    /// `~/Library/Preferences/Blizzard/Hearthstone/log.config`. The client reads it at launch.
    public var logConfigFile: URL

    public init(installDirectory: URL, logConfigFile: URL) {
        self.installDirectory = installDirectory
        self.logConfigFile = logConfigFile
    }

    /// The standard install at `/Applications/Hearthstone`.
    public static var standard: HearthstoneLocations {
        HearthstoneLocations(
            installDirectory: URL(filePath: "/Applications/Hearthstone", directoryHint: .isDirectory),
            logConfigFile: FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Preferences/Blizzard/Hearthstone/log.config")
        )
    }

    /// The standard locations, with the install directory taken from a running
    /// client's bundle (`<install>/Hearthstone.app`) when there is one.
    public static func forRunningApp(bundleURL: URL?) -> HearthstoneLocations {
        var locations = standard
        if let bundleURL {
            locations.installDirectory = bundleURL.deletingLastPathComponent()
        }
        return locations
    }

    /// One folder per client launch lives here: `Hearthstone_YYYY_MM_DD_HH_MM_SS`.
    public var logsDirectory: URL {
        installDirectory.appending(path: "Logs", directoryHint: .isDirectory)
    }

    /// Holds `[Log] FileSizeLimit.Int=-1`, which lifts the per-file log size cap.
    public var clientConfigFile: URL {
        installDirectory.appending(path: "client.config")
    }
}
