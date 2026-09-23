import Foundation
import Observation
import TavernEngine

/// Card data for the running Hearthstone build, loaded once per launch: from the cache,
/// or downloaded once for a new build, or the newest cached build when offline.
@MainActor
@Observable
final class CardDataModel {
    static let shared = CardDataModel()

    private(set) var loaded: LoadedCardData?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    var cards: CardDB? { loaded?.db }

    var statusText: String {
        if isLoading { return "Loading card data…" }
        if let errorMessage { return "No card data: \(errorMessage)" }
        guard let loaded else { return "Card data not loaded" }
        let build = loaded.db.build.map { "build \($0)" } ?? "latest build"
        let count = "\(loaded.db.count.formatted()) cards"
        switch loaded.origin {
        case .cache: return "Card data: \(build), \(count), cached"
        case .downloaded: return "Card data: \(build), \(count), downloaded"
        case .fallback(let reason):
            let wanted = loaded.requestedBuild.map { " (wanted build \($0))" } ?? ""
            return "Card data: \(build)\(wanted), \(count), stale: \(reason)"
        }
    }

    func loadIfNeeded() {
        guard loaded == nil, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                loaded = try await Task.detached(priority: .userInitiated) {
                    try await CardDataStore().load(build: HearthstoneBuild.installed())
                }.value
            } catch {
                errorMessage = "\(error)"
            }
            isLoading = false
        }
    }
}
