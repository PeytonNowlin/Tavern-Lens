/// Log configuration across the client's lifetime, and the "restart required" signal.
///
/// The client reads its log config only at launch. So a repair made while it runs
/// (or as it launches) only takes effect after a restart: until the client quits,
/// `restartRequired` is true. A repair made while it isn't running needs nothing.
///
/// Call `check(hearthstoneRunning:)` when the app starts and whenever the client
/// launches; call `hearthstoneTerminated()` when it quits.
public struct LogSetup: Sendable {
    public let locations: HearthstoneLocations
    public private(set) var restartRequired = false
    public private(set) var lastReport: LogConfigReport?

    public init(locations: HearthstoneLocations) {
        self.locations = locations
    }

    /// Checks and repairs both config files.
    @discardableResult
    public mutating func check(hearthstoneRunning: Bool) -> LogConfigReport {
        let report = LogConfig.ensure(at: locations)
        lastReport = report
        if report.changedAnything, hearthstoneRunning {
            restartRequired = true
        }
        return report
    }

    /// The client quit, so its next launch reads the repaired config.
    public mutating func hearthstoneTerminated() {
        restartRequired = false
    }
}
