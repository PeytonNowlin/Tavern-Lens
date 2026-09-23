import Foundation
import Observation
import TavernEngine

/// Replays a chosen Power.log off the main thread and holds the result for the debug window.
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

    func replay(_ url: URL, cards: CardDB? = nil) {
        fileURL = url
        result = nil
        errorMessage = nil
        elapsed = nil
        isReplaying = true
        Task {
            let clock = ContinuousClock()
            let start = clock.now
            do {
                let replayed = try await Task.detached(priority: .userInitiated) {
                    try TavernEngine.replay(fileAt: url, cards: cards)
                }.value
                result = replayed
            } catch {
                errorMessage = error.localizedDescription
            }
            elapsed = clock.now - start
            isReplaying = false
        }
    }
}
