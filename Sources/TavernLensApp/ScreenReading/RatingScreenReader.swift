import AppKit
import Observation
import os
import ScreenReading

/// Reads only the Battlegrounds lobby, using the existing Screen Recording grant.
/// Captures stay in memory; gameplay and other applications are never sampled.
@MainActor @Observable
final class RatingScreenReader {
    private static let log = Logger(subsystem: "com.nowlinautomation.TavernLens", category: "screen")
    private(set) var permissionGranted = ScreenRecordingPermission.isGranted
    private(set) var statusText = "Automatic MMR reading waits for the Battlegrounds lobby. You can also enter your rating below."
    @ObservationIgnored private let live: LiveTrackingModel
    @ObservationIgnored private let history: RatingHistoryModel
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var inLobby = false
    @ObservationIgnored private var completedGameSeed: Int?

    init(live: LiveTrackingModel, history: RatingHistoryModel) {
        self.live = live
        self.history = history
    }

    func start() {
        observe()
        stateChanged()
    }

    func gameEnded(seed: Int?) { completedGameSeed = seed }

    func refreshPermission() {
        permissionGranted = ScreenRecordingPermission.isGranted
        if canReadLobby {
            inLobby = false
            stateChanged()
        }
    }

    func requestPermission() {
        permissionGranted = ScreenRecordingPermission.request()
        if permissionGranted { refreshPermission() }
    }

    private var canReadLobby: Bool {
        live.hearthstone != nil && live.update.scene == "BACON" && live.update.state.status != .inGame
    }

    private func observe() {
        withObservationTracking {
            _ = live.update
            _ = live.hearthstone
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.stateChanged()
                self?.observe()
            }
        }
    }

    private func stateChanged() {
        let lobby = canReadLobby
        guard lobby != inLobby else { return }
        inLobby = lobby
        task?.cancel()
        task = nil
        guard lobby else {
            statusText = "MMR is read between games when the rating is visible in the Battlegrounds lobby."
            return
        }
        permissionGranted = ScreenRecordingPermission.isGranted
        guard permissionGranted else {
            statusText = "Automatic MMR reading needs Screen Recording access. You can enter your rating below."
            return
        }
        statusText = "Looking for a clear, stable MMR in the Battlegrounds lobby…"
        task = Task { [weak self] in
            var stable = StableRatingReading()
            for attempt in 0..<24 {
                // Wait for the lobby transition, then confirm the stable total promptly
                // so a player can queue again without spending 15 seconds in the lobby.
                // Keep retrying more slowly if an animation or dialog obscures the rating.
                let delay: Duration = attempt == 0 ? .seconds(2) : (attempt < 3 ? .seconds(1) : .seconds(5))
                do { try await Task.sleep(for: delay) } catch { return }
                guard let self, !Task.isCancelled, self.canReadLobby else { return }
                let rating = await self.captureRating()
                guard !Task.isCancelled, self.canReadLobby else { return }
                guard let value = stable.observe(rating) else { continue }
                if await self.history.record(value, source: .screen, gameSeed: self.completedGameSeed) {
                    self.statusText = "Last automatic reading: \(value.formatted()) MMR."
                } else {
                    self.statusText = "MMR was read, but could not be saved. See the history error below."
                }
                return
            }
            self?.statusText = "No clear MMR reading found. Open the Battlegrounds lobby again, or enter your rating below."
        }
    }

    private func captureRating() async -> Int? {
        let context: HearthstoneRegionContext
        switch await HearthstoneRegionContext.locate(pid: live.hearthstone?.processIdentifier) {
        case .success(let found): context = found
        case .failure(let failure):
            Self.log.info("Rating read skipped: \(failure.description, privacy: .public)")
            return nil
        }
        let content = context.window.contentFrame
        let image: CGImage
        switch await context.captureRegion(CGRect(origin: .zero, size: content.size)) {
        case .success(let captured): image = captured
        case .failure(let failure):
            Self.log.error("Rating capture failed: \(failure.description, privacy: .public)")
            if failure == .noPermission { permissionGranted = false }
            return nil
        }
        let rect = CGRect(origin: .zero, size: content.size)
        do {
            return try await Task.detached(priority: .utility) {
                let lines = try HeroPickBannerReader.recognizeLines(in: image, showing: rect)
                return RatingScreenParser.rating(in: lines)
            }.value
        } catch {
            Self.log.error("Rating recognition failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
