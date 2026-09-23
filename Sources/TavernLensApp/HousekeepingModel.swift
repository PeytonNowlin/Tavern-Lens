import Foundation
import HSLog
import Observation
import TavernEngine

/// The retention limits, saved in user defaults. Every housekeeping pass reads the
/// current values, so a change applies to the next pass.
@MainActor
@Observable
final class RetentionSettingsModel {
    static let defaultsKey = "retentionSettings"

    var settings: RetentionSettings {
        didSet {
            guard settings != oldValue, let data = try? JSONEncoder().encode(settings) else { return }
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(RetentionSettings.self, from: $0) } ?? RetentionSettings()
    }

    func resetToDefaults() {
        settings = RetentionSettings()
    }
}

/// Runs log housekeeping (`LogHousekeeper`) off the main thread: at launch and after
/// each game ends. Passes never overlap; a request made during a pass runs one more
/// pass after it.
@MainActor
@Observable
final class HousekeepingModel {
    private(set) var isRunning = false
    private(set) var lastRun: Date?
    private(set) var lastReport: HousekeepingReport?

    @ObservationIgnored private let settings: RetentionSettingsModel
    @ObservationIgnored private let live: LiveTrackingModel
    @ObservationIgnored private var runAgain = false

    init(settings: RetentionSettingsModel, live: LiveTrackingModel) {
        self.settings = settings
        self.live = live
    }

    func run() {
        guard !isRunning else {
            runAgain = true
            return
        }
        isRunning = true
        let housekeeper = LogHousekeeper(
            logsDirectory: live.logsDirectory, records: .standard, replays: .standard, artCache: ArtCache()
        )
        let settings = settings.settings
        // The session the app follows; the newest folder and open ones are protected anyway.
        let active = Set([live.update.session?.name].compactMap { $0 })
        Task {
            let report = await Task.detached(priority: .utility) {
                housekeeper.run(settings: settings, activeSessions: active)
            }.value
            lastReport = report
            lastRun = Date()
            isRunning = false
            if runAgain {
                runAgain = false
                run()
            }
        }
    }

    var summary: String {
        if isRunning { return "Cleaning up…" }
        guard let report = lastReport, let lastRun else { return "Not run yet" }
        var parts = ["\(report.logs.sessionsRemaining) log sessions, \(ByteSize.format(report.logs.bytesRemaining))"]
        if !report.logs.deleted.isEmpty {
            parts.append("deleted \(report.logs.deleted.count) (\(ByteSize.format(report.logs.bytesFreed)))")
        }
        let unrecorded = report.logs.kept.values.filter { $0 == .unrecorded }.count
        if unrecorded > 0 { parts.append("kept \(unrecorded) with unrecorded games") }
        if !report.replaysSaved.isEmpty { parts.append("saved \(report.replaysSaved.count) replay(s)") }
        return "Last cleanup \(lastRun.formatted(date: .omitted, time: .shortened)): " + parts.joined(separator: ", ")
    }
}
