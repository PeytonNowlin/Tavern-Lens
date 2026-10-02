import AppKit
import Observation
import ScreenReading

/// Reads only the Battlegrounds lobby, using the existing Screen Recording grant.
/// Captures stay in memory; gameplay and other applications are never sampled.
@MainActor @Observable
final class RatingScreenReader {
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
        guard ScreenRecordingPermission.isGranted else {
            statusText = "Automatic MMR reading needs Screen Recording access. You can enter your rating below."
            return
        }
        statusText = "Looking for a clear, stable MMR in the Battlegrounds lobby…"
        task = Task { [weak self] in
            var stable = StableRatingReading()
            for _ in 0..<24 {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
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
        guard let pid = live.hearthstone?.processIdentifier,
              let window = HearthstoneWindowTracker.locate(pid: pid) else { return nil }
        do {
            let image = try await BannerCapture.capture(pid: pid, rect: window.contentFrame)
            let rect = CGRect(origin: .zero, size: window.contentFrame.size)
            return try await Task.detached(priority: .utility) {
                let lines = try HeroPickBannerReader.recognizeLines(in: image, showing: rect)
                return RatingScreenParser.rating(in: lines)
            }.value
        } catch { return nil }
    }
}
