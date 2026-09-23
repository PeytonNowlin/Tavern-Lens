import Foundation
import HSLog
import Observation
import TavernEngine

/// Replays a chosen Power.log, or a saved replay (`*.power.log.gz`), off the main
/// thread and holds the result for the debug window.
@MainActor
@Observable
final class DebugReplayModel {
    private(set) var fileURL: URL?
    private(set) var result: ReplayResult?
    private(set) var isReplaying = false
    private(set) var errorMessage: String?
    private(set) var elapsed: Duration?

    var menuStatus: String {
        if isReplaying { return "Replaying log…" }
        guard let result else { return "No log replayed" }
        return "Debug replay: \(result.games.count) Battlegrounds game(s)"
    }

    /// Saved replays, newest first, for the debug window's menu.
    private(set) var savedReplays: [ReplayFile] = []

    func refreshSavedReplays() {
        savedReplays = ReplayStore.standard.all().reversed()
    }

    func replay(
        _ url: URL, cards: CardDB? = nil, pool: MinionPool? = PoolDataModel.shared.pool,
        builds: BuildCatalog? = BuildDataModel.shared.catalog
    ) {
        if let saved = ReplayFile(url: url) {
            run(url) { try TavernEngine.replay(saved, cards: cards, pool: pool) }
        } else {
            run(url) {
                try TavernEngine.replay(
                    fileAt: url, cards: cards, pool: pool, builds: builds,
                    session: LogSession(directory: url.deletingLastPathComponent())
                )
            }
        }
    }

    private func run(_ url: URL, _ work: @escaping @Sendable () throws -> ReplayResult) {
        fileURL = url
        result = nil
        errorMessage = nil
        elapsed = nil
        isReplaying = true
        Task {
            let clock = ContinuousClock()
            let start = clock.now
            do {
                let replayed = try await Task.detached(priority: .userInitiated, operation: work).value
                result = replayed
            } catch {
                errorMessage = error.localizedDescription
            }
            elapsed = clock.now - start
            isReplaying = false
        }
    }
}
